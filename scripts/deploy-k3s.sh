#!/bin/bash
# ================================================================
# scripts/deploy-k3s.sh
# Deploys Online Boutique to k3s on a single EC2 node
#
# Usage:
#   ./scripts/deploy-k3s.sh
#   ./scripts/deploy-k3s.sh --skip-build   # skip Docker builds
#   ./scripts/deploy-k3s.sh --reset        # wipe and redeploy
# ================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

SKIP_BUILD=false
DO_RESET=false
REPO_DIR="/opt/sre-demo"
K8S_DIR="$REPO_DIR/k8s"

while [[ $# -gt 0 ]]; do
  case $1 in
    --skip-build) SKIP_BUILD=true; shift ;;
    --reset)      DO_RESET=true;   shift ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

log()     { echo -e "$1"; }
section() { echo -e "\n${BOLD}${CYAN}── $1 ──${RESET}"; }
pass()    { echo -e "  ${GREEN}✓${RESET} $1"; }
fail()    { echo -e "  ${RED}✗${RESET} $1"; exit 1; }
warn()    { echo -e "  ${YELLOW}⚠${RESET} $1"; }

# ================================================================
# PREFLIGHT
# ================================================================
section "Preflight checks"

command -v kubectl &>/dev/null || fail "kubectl not found — is k3s installed?"
command -v docker  &>/dev/null || fail "docker not found"
kubectl get nodes &>/dev/null  || fail "Cannot reach k3s — run: export KUBECONFIG=~/.kube/config"
pass "k3s is reachable"

NODE_STATUS=$(kubectl get nodes --no-headers | awk '{print $2}')
[[ "$NODE_STATUS" == "Ready" ]] || fail "Node is not Ready (status: $NODE_STATUS)"
pass "Node is Ready"

[[ -d "$K8S_DIR" ]] || fail "k8s/ directory not found at $K8S_DIR"
pass "k8s manifests found"

# ================================================================
# RESET
# ================================================================
if $DO_RESET; then
  section "Resetting namespace"
  warn "Deleting all resources in boutique namespace..."
  kubectl delete namespace boutique --ignore-not-found=true
  kubectl wait --for=delete namespace/boutique --timeout=60s 2>/dev/null || true
  pass "Namespace cleared"
fi

# ================================================================
# FIX MANIFESTS FOR K3S
# ================================================================
section "Patching manifests for k3s"

# storage class
find "$K8S_DIR" -name "*.yaml" -exec \
  sed -i 's/storageClassName: gp2/storageClassName: local-path/g' {} \;
pass "Storage class: gp2 -> local-path"

# image references
find "$K8S_DIR" -name "*.yaml" -exec \
  sed -i 's|YOUR_ECR_REPO/|boutique/|g' {} \;
pass "Image references updated"

# imagePullPolicy
if ! grep -q "imagePullPolicy: Never" "$K8S_DIR/services/services.yaml"; then
  sed -i '/image: boutique\//a\          imagePullPolicy: Never' \
    "$K8S_DIR/services/services.yaml"
  pass "imagePullPolicy: Never added"
else
  pass "imagePullPolicy already set"
fi

# replicas: 1 for single node
sed -i 's/replicas: 2/replicas: 1/g' "$K8S_DIR/services/services.yaml"
pass "Replicas set to 1"

# postgres headless -> ClusterIP
sed -i '/^  clusterIP: None/d' "$K8S_DIR/postgres/postgres.yaml" 2>/dev/null || true
pass "Postgres service set to ClusterIP"

# ================================================================
# BUILD + IMPORT IMAGES
# ================================================================
if ! $SKIP_BUILD; then
  section "Building Docker images"
  cd "$REPO_DIR"

  declare -A SERVICES=(
    ["frontend"]="src/frontend"
    ["productcatalogservice"]="src/productcatalogservice"
    ["checkoutservice"]="src/checkoutservice"
    ["authservice"]="src/authservice"
    ["cartservice"]="src/cartservice/src"
  )

  for service in "${!SERVICES[@]}"; do
    log "  Building boutique/$service..."
    docker build -t "boutique/$service:latest" "${SERVICES[$service]}" --quiet
    pass "$service built"
  done

  section "Importing images into k3s"
  for service in "${!SERVICES[@]}"; do
    log "  Importing $service..."
    docker save "boutique/$service:latest" | sudo k3s ctr images import - > /dev/null
    pass "$service imported"
  done
fi

# ================================================================
# DEPLOY
# ================================================================
section "Deploying to k3s"

kubectl apply -f "$K8S_DIR/namespace/"
pass "Namespace"

kubectl apply -f "$K8S_DIR/configmap/"
kubectl apply -f "$K8S_DIR/secrets/"
pass "ConfigMap + Secrets"

kubectl apply -f "$K8S_DIR/postgres/"
kubectl apply -f "$K8S_DIR/redis/"
pass "Postgres + Redis applied"

log "  Waiting for postgres (up to 90s)..."
kubectl rollout status statefulset/postgres -n boutique --timeout=90s
pass "Postgres ready"

log "  Waiting for redis (up to 60s)..."
kubectl rollout status deployment/redis -n boutique --timeout=60s
pass "Redis ready"

kubectl apply -f "$K8S_DIR/services/"
pass "Application services applied"

kubectl apply -f "$K8S_DIR/monitoring/"
pass "Monitoring applied"

warn "Skipping HPA — single node cluster"
warn "Skipping ALB ingress — using NodePort"

# ================================================================
# WAIT FOR PODS
# ================================================================
section "Waiting for pods"

for deploy in frontend productcatalogservice checkoutservice authservice cartservice prometheus grafana; do
  log "  Waiting for $deploy..."
  if kubectl rollout status deployment/"$deploy" -n boutique --timeout=120s 2>/dev/null; then
    pass "$deploy ready"
  else
    warn "$deploy not ready — check: kubectl logs -n boutique deployment/$deploy"
  fi
done

# ================================================================
# SUMMARY
# ================================================================
section "Deployment Summary"

kubectl get pods -n boutique

EXTERNAL_IP=$(curl -s --max-time 5 \
  http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || \
  kubectl get nodes -o jsonpath='{.items[0].status.addresses[0].address}')

log ""
log "${BOLD}${GREEN}Deployment complete${RESET}"
log ""
log "  App:        ${CYAN}http://$EXTERNAL_IP:30080${RESET}"
log "  Grafana:    ${CYAN}http://$EXTERNAL_IP:30030${RESET}  (admin/admin)"
log "  Prometheus: ${CYAN}http://$EXTERNAL_IP:9090${RESET}"
log ""
log "  ${CYAN}kubectl get pods -n boutique${RESET}"
log "  ${CYAN}kubectl get svc  -n boutique${RESET}"
log "  ${CYAN}kubectl logs -n boutique deployment/<service>${RESET}"
