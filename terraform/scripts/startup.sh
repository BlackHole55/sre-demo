#!/bin/bash
set -euo pipefail
exec > /var/log/boutique-init.log 2>&1

echo "=== [1/5] System update ==="
apt-get update -y
apt-get upgrade -y

echo "=== [2/5] Install Docker ==="
apt-get install -y ca-certificates curl gnupg git

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    > /etc/apt/sources.list.d/docker.list

apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

systemctl enable docker
systemctl start docker

echo "=== Adding swap to compensate for low RAM ==="
fallocate -l 2G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab

usermod -aG docker ubuntu

echo "=== [3/5] Clone repository ==="
git clone https://github.com/BlackHole55/sre-demo.git /opt/sre-demo
chown -R ubuntu:ubuntu /opt/sre-demo

echo "=== [4/5] Install k3s ==="
curl -sfL https://get.k3s.io | sh -

# set up kubectl for ubuntu user
chmod 644 /etc/rancher/k3s/k3s.yaml
mkdir -p /home/ubuntu/.kube
cp /etc/rancher/k3s/k3s.yaml /home/ubuntu/.kube/config
chown ubuntu:ubuntu /home/ubuntu/.kube/config

# wait for node to be ready
echo "Waiting for k3s node to be ready..."
until sudo k3s kubectl get nodes | grep -q "Ready"; do
  sleep 5
done
echo "k3s node is Ready"

echo "=== [5/5] Deploy to k3s ==="
cd /opt/sre-demo

# create .env
cp .env.template .env

# build images as root (docker is available)
for service in frontend productcatalogservice checkoutservice authservice cartservice; do
  echo "Building boutique/$service..."
  docker build -t boutique/$service:latest src/$service/ 2>/dev/null || \
  docker build -t boutique/$service:latest src/$service/src/ 2>/dev/null || true
done

# import into k3s
for service in frontend productcatalogservice checkoutservice authservice cartservice; do
  echo "Importing $service into k3s..."
  docker save boutique/$service:latest | k3s ctr images import - || true
done

# deploy
chmod +x scripts/deploy-k3s.sh
bash scripts/deploy-k3s.sh --skip-build

echo "=== Boot complete ==="

# [Service]
# Type=oneshot
# RemainAfterExit=yes
# WorkingDirectory=/opt/sre-demo
# ExecStart=/usr/bin/docker compose up -d
# ExecStop=/usr/bin/docker compose down
# User=ubuntu
# Group=ubuntu

# [Install]
# WantedBy=multi-user.target
# SERVICE

# systemctl daemon-reload
# systemctl enable boutique.service

# echo "=== Boot complete. Stack is starting. ==="