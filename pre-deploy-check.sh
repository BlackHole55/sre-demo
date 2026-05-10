#!/bin/bash

set -euo pipefail

# ── Colours ──────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# ── Defaults ─────────────────────────────────────────────────────
ENV_FILE=".env"
DEPLOY=false
ERRORS=0
WARNINGS=0

# ── Argument parsing ─────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case $1 in
    --deploy)    DEPLOY=true; shift ;;
    --env)       ENV_FILE="$2"; shift 2 ;;
    --help)
      echo "Usage: $0 [--deploy] [--env FILE]"
      echo "  --deploy      Run docker compose up after successful validation"
      echo "  --env FILE    Path to env file (default: .env)"
      exit 0 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# ── Load env file if it exists ───────────────────────────────────
if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
  echo -e "${CYAN}Loaded env file: $ENV_FILE${RESET}"
fi

# ── Helper functions ─────────────────────────────────────────────
pass() { echo -e "  ${GREEN}✓${RESET} $1"; }
fail() { echo -e "  ${RED}✗${RESET} $1"; ERRORS=$((ERRORS + 1)); }
warn() { echo -e "  ${YELLOW}⚠${RESET} $1"; WARNINGS=$((WARNINGS + 1)); }

section() {
  echo ""
  echo -e "${BOLD}${CYAN}── $1 ──${RESET}"
}

# ── DSN parser ───────────────────────────────────────────────────
# Parses postgres://user:pass@host:port/db?params
parse_dsn() {
  local dsn="$1"
  local field="$2"

  case $field in
    scheme)   echo "$dsn" | grep -oP '^[a-z]+(?=://)' ;;
    user)     echo "$dsn" | grep -oP '(?<=://)[^:]+(?=:)' ;;
    host)     echo "$dsn" | grep -oP '(?<=@)[^:/]+' ;;
    port)     echo "$dsn" | grep -oP '(?<=:)\d+(?=/)' | tail -1 ;;
    database) echo "$dsn" | grep -oP '(?<=/)[^?]+' ;;
  esac
}

# ================================================================
# 1. REQUIRED ENVIRONMENT VARIABLES
# ================================================================
section "Required Environment Variables"

# ── PostgreSQL ───────────────────────────────────────────────────
required_vars=(
  "POSTGRES_USER"
  "POSTGRES_PASSWORD"
  "POSTGRES_DB"
)

for var in "${required_vars[@]}"; do
  if [[ -z "${!var:-}" ]]; then
    fail "$var is not set"
  else
    # mask passwords in output
    if [[ "$var" == *"PASSWORD"* ]] || [[ "$var" == *"SECRET"* ]]; then
      pass "$var = ****"
    else
      pass "$var = ${!var}"
    fi
  fi
done

# ── Service DSNs ─────────────────────────────────────────────────
dsn_vars=(
  "PRODUCTCATALOG_POSTGRES_DSN"
  "CHECKOUT_POSTGRES_DSN"
  "AUTH_POSTGRES_DSN"
)

for var in "${dsn_vars[@]}"; do
  if [[ -z "${!var:-}" ]]; then
    warn "$var not set — will use docker-compose.yml default"
  else
    pass "$var is set"
  fi
done

# ── Optional but recommended ─────────────────────────────────────
optional_vars=(
  "GRAFANA_PASSWORD"
)

for var in "${optional_vars[@]}"; do
  if [[ -z "${!var:-}" ]]; then
    warn "$var not set — using default (not recommended for production)"
  else
    pass "$var is set"
  fi
done

# ================================================================
# 2. DOCKER COMPOSE FILE VALIDATION
# ================================================================
section "Docker Compose File"

if [[ ! -f "docker-compose.yml" ]]; then
  fail "docker-compose.yml not found in current directory"
else
  pass "docker-compose.yml found"

  # validate compose file syntax
  if docker compose config --quiet 2>/dev/null; then
    pass "docker-compose.yml syntax is valid"
  else
    fail "docker-compose.yml has syntax errors:"
    docker compose config 2>&1 | head -20
  fi
fi

# ================================================================
# 3. DATABASE CONNECTION STRING VALIDATION
# ================================================================
section "Database Connection String Validation"

validate_dsn() {
  local service="$1"
  local dsn="$2"

  if [[ -z "$dsn" ]]; then
    warn "$service — DSN not provided, skipping validation"
    return
  fi

  local scheme host port database

  # check scheme
  scheme=$(parse_dsn "$dsn" scheme)
  if [[ "$scheme" != "postgres" ]]; then
    fail "$service — invalid DSN scheme: '$scheme' (expected: postgres)"
    return
  fi

  # check host is not empty
  host=$(parse_dsn "$dsn" host)
  if [[ -z "$host" ]]; then
    fail "$service — DSN missing hostname"
    return
  fi

  # check port is numeric
  port=$(parse_dsn "$dsn" port)
  if [[ -z "$port" ]]; then
    warn "$service — DSN missing port (will use default 5432)"
  elif ! [[ "$port" =~ ^[0-9]+$ ]]; then
    fail "$service — DSN port is not numeric: '$port'"
    return
  elif [[ "$port" -lt 1 ]] || [[ "$port" -gt 65535 ]]; then
    fail "$service — DSN port out of range: '$port'"
    return
  fi

  # check database name
  database=$(parse_dsn "$dsn" database)
  if [[ -z "$database" ]]; then
    fail "$service — DSN missing database name"
    return
  fi

  # check for common mistakes
  if echo "$dsn" | grep -q "localhost" && [[ "${CI:-}" != "true" ]]; then
    warn "$service — DSN uses 'localhost' which won't work inside Docker (use service name e.g. 'postgres')"
  fi

  if echo "$dsn" | grep -q "127.0.0.1"; then
    warn "$service — DSN uses '127.0.0.1' which won't work inside Docker"
  fi

  if echo "$dsn" | grep -qP "password=\s*&|:@"; then
    warn "$service — DSN appears to have an empty password"
  fi

  pass "$service — DSN valid (host=$host, port=${port:-5432}, db=$database)"
}

# Read DSNs from docker-compose.yml if not in env
PRODUCTCATALOG_DSN="${PRODUCTCATALOG_POSTGRES_DSN:-postgres://boutique:boutique@postgres:5432/boutique?sslmode=disable&search_path=products}"
CHECKOUT_DSN="${CHECKOUT_POSTGRES_DSN:-postgres://boutique:boutique@postgres:5432/boutique?sslmode=disable&search_path=orders}"
AUTH_DSN="${AUTH_POSTGRES_DSN:-postgres://boutique:boutique@postgres:5432/boutique?sslmode=disable&search_path=auth}"

validate_dsn "productcatalogservice" "$PRODUCTCATALOG_DSN"
validate_dsn "checkoutservice"       "$CHECKOUT_DSN"
validate_dsn "authservice"           "$AUTH_DSN"

# ================================================================
# 4. SERVICE ENDPOINT VALIDATION
# ================================================================
section "Service Endpoint Format Validation"

validate_endpoint() {
  local service="$1"
  local endpoint="$2"
  local optional="${3:-false}"

  if [[ -z "$endpoint" ]]; then
    if [[ "$optional" == "true" ]]; then
      pass "$service — not configured (optional)"
    else
      fail "$service — endpoint is empty (required)"
    fi
    return
  fi

  # must be host:port format
  if ! echo "$endpoint" | grep -qP '^[a-zA-Z0-9_-]+:\d+$'; then
    fail "$service — invalid endpoint format '$endpoint' (expected: hostname:port)"
    return
  fi

  local host port
  host=$(echo "$endpoint" | cut -d: -f1)
  port=$(echo "$endpoint" | cut -d: -f2)

  # port must be in valid range
  if [[ "$port" -lt 1 ]] || [[ "$port" -gt 65535 ]]; then
    fail "$service — port out of range: $port"
    return
  fi

  # warn about localhost
  if [[ "$host" == "localhost" ]] || [[ "$host" == "127.0.0.1" ]]; then
    warn "$service — endpoint uses '$host' which won't resolve between containers"
    return
  fi

  pass "$service — endpoint valid ($endpoint)"
}

# Extract endpoints from compose file
PRODUCT_CATALOG_ADDR=$(docker compose config 2>/dev/null | \
  grep "PRODUCT_CATALOG_SERVICE_ADDR" | head -1 | \
  grep -oP '[\w-]+:\d+' || echo "productcatalogservice:3550")

CHECKOUT_ADDR=$(docker compose config 2>/dev/null | \
  grep "CHECKOUT_SERVICE_ADDR" | head -1 | \
  grep -oP '[\w-]+:\d+' || echo "checkoutservice:5050")

CART_ADDR=$(docker compose config 2>/dev/null | \
  grep "CART_SERVICE_ADDR" | head -1 | \
  grep -oP '[\w-]+:\d+' || echo "cartservice:7070")

AUTH_ADDR=$(docker compose config 2>/dev/null | \
  grep "AUTH_SERVICE_ADDR" | head -1 | \
  grep -oP '[\w-]+:\d+' || echo "authservice:9555")

validate_endpoint "productcatalogservice" "$PRODUCT_CATALOG_ADDR"
validate_endpoint "checkoutservice"       "$CHECKOUT_ADDR"
validate_endpoint "cartservice"           "$CART_ADDR"
validate_endpoint "authservice"           "$AUTH_ADDR"

# ================================================================
# 5. LIVE CONNECTIVITY CHECKS (if stack is already running)
# ================================================================
section "Live Connectivity Checks (if stack is running)"

check_live() {
  local service="$1"
  local container="$2"
  local check_cmd="$3"

  local cid
  cid=$(docker compose ps -q "$container" 2>/dev/null || echo "")

  if [[ -z "$cid" ]]; then
    warn "$service — container not running, skipping live check"
    return
  fi

  if docker exec "$cid" sh -c "$check_cmd" > /dev/null 2>&1; then
    pass "$service — live check passed"
  else
    fail "$service — live check FAILED"
  fi
}

# postgres reachable
check_live "PostgreSQL" "postgres" \
  "pg_isready -U ${POSTGRES_USER:-boutique} -d ${POSTGRES_DB:-boutique}"

# redis reachable
check_live "Redis" "redis" \
  "redis-cli ping | grep -q PONG"

# frontend responding
check_live "Frontend HTTP" "frontend" \
  "wget -qO- http://localhost:8080/_healthz"

# productcatalog health
check_live "ProductCatalog health" "productcatalogservice" \
  "wget -qO- http://localhost:9090/health"

# checkoutservice health
check_live "Checkout health" "checkoutservice" \
  "wget -qO- http://localhost:9090/health"

# authservice health
check_live "Auth health" "authservice" \
  "wget -qO- http://localhost:9090/health"

# ================================================================
# 6. REQUIRED FILES CHECK
# ================================================================
section "Required Files"

required_files=(
  "docker-compose.yml"
  "nginx/nginx.conf"
  "db/init.sql"
  "monitoring/prometheus.yml"
  "monitoring/alert_rules.yml"
  "monitoring/loki/loki.yml"
  "monitoring/loki/promtail.yml"
)

for f in "${required_files[@]}"; do
  if [[ -f "$f" ]]; then
    pass "$f exists"
  else
    fail "$f is MISSING"
  fi
done

# ================================================================
# SUMMARY
# ================================================================
echo ""
echo -e "${BOLD}════════════════════════════════════════${RESET}"
echo -e "${BOLD}  Pre-deployment Check Summary${RESET}"
echo -e "${BOLD}════════════════════════════════════════${RESET}"

if [[ "$ERRORS" -gt 0 ]]; then
  echo -e "  ${RED}${BOLD}✗ $ERRORS error(s) found — deployment blocked${RESET}"
fi

if [[ "$WARNINGS" -gt 0 ]]; then
  echo -e "  ${YELLOW}⚠ $WARNINGS warning(s) — review before deploying${RESET}"
fi

if [[ "$ERRORS" -eq 0 ]] && [[ "$WARNINGS" -eq 0 ]]; then
  echo -e "  ${GREEN}${BOLD}✓ All checks passed${RESET}"
fi

echo ""

# ── Deploy or exit ────────────────────────────────────────────────
if [[ "$ERRORS" -gt 0 ]]; then
  echo -e "${RED}Deployment blocked. Fix errors above and re-run.${RESET}"
  exit 1
fi

if $DEPLOY; then
  echo -e "${GREEN}All checks passed. Starting deployment...${RESET}"
  echo ""
  docker compose up --build -d
  echo ""
  echo -e "${GREEN}${BOLD}✓ Deployment complete${RESET}"
else
  echo -e "${CYAN}Run with --deploy to start the stack after validation.${RESET}"
  echo -e "${CYAN}Example: $0 --deploy${RESET}"
fi