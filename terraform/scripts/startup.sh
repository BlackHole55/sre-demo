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

echo "=== [4/5] Start stack ==="
cd /opt/sre-demo
docker compose pull --ignore-pull-failures || true
docker compose up --build -d

echo "=== [5/5] Enable auto-start on reboot ==="
cat > /etc/systemd/system/boutique.service <<'SERVICE'
[Unit]
Description=Online Boutique Docker Compose Stack
After=docker.service network-online.target
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/sre-demo
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
User=ubuntu
Group=ubuntu

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable boutique.service

echo "=== Boot complete. Stack is starting. ==="