#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && cd .. && pwd )"

source "$BASE_DIR/.env"

sudo systemctl stop deploy-worker.timer || true
sudo systemctl stop deploy-worker.service || true
sudo systemctl disable deploy-worker.timer || true
sudo systemctl disable deploy-worker.service || true
sudo rm -f /etc/systemd/system/deploy-worker.service || true
sudo rm -f /etc/systemd/system/deploy-worker.timer || true

cat <<EOF | sudo tee /etc/systemd/system/deploy-worker.service
[Unit]
Description=Deploy Worker Job
After=network.target

[Service]
Environment="PATH=$PATH"
Type=simple
User=$DEPLOY_USER
Group=$DEPLOY_USER
WorkingDirectory=$BASE_DIR
ExecStart=$BASE_DIR/bin/deploy-worker
Restart=on-failure
RestartSec=5

# Capture logs in journal
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target

EOF

cat <<EOF | sudo tee /etc/sudoers.d/10-deploy
# nginx
$DEPLOY_USER ALL=(ALL) NOPASSWD: /usr/sbin/nginx -t
$DEPLOY_USER ALL=(ALL) NOPASSWD: /usr/sbin/nginx -s reload

# supervisor – restrict to horizon workers
$DEPLOY_USER ALL=(ALL) NOPASSWD: /usr/bin/supervisorctl reload
$DEPLOY_USER ALL=(ALL) NOPASSWD: /usr/bin/systemctl reload caddy
$DEPLOY_USER ALL=(ALL) NOPASSWD: /usr/bin/supervisorctl restart horizon-*
EOF

sudo visudo -cf /etc/sudoers.d/10-deploy || (echo "ERROR in sudoers file" && exit 1)
sudo systemctl daemon-reload
sudo systemctl enable --now deploy-worker.service
