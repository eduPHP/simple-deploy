#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && cd .. && pwd )"

source "$BASE_DIR/.env"

composer install --no-interaction --prefer-dist --optimize-autoloader --no-dev --no-scripts --no-ansi
sudo systemctl stop deploy-worker.timer
sudo systemctl stop deploy-worker.service
sudo systemctl disable deploy-worker.timer
sudo systemctl disable deploy-worker.service
sudo rm -f /etc/systemd/system/deploy-worker.service
sudo rm -f /etc/systemd/system/deploy-worker.timer

cat <<EOF | sudo tee /etc/systemd/system/deploy-worker.service
[Unit]
Description=Deploy Worker Job
After=network.target

[Service]
Type=oneshot
User=$DEPLOY_USER
Group=$DEPLOY_USER
WorkingDirectory=$BASE_DIR
ExecStart=$BASE_DIR/bin/deploy-worker

# Capture logs in journal
StandardOutput=journal
StandardError=journal

EOF

cat <<EOF | sudo tee /etc/systemd/system/deploy-worker.timer
[Unit]
Description=Run Deploy Worker every 10 seconds

[Timer]
OnBootSec=10s
OnUnitInactiveSec=10s
Unit=deploy-worker.service
Persistent=true

[Install]
WantedBy=timers.target

EOF

cat <<EOF | sudo tee /etc/sudoers.d/10-deploy
# nginx
$DEPLOY_USER ALL=(ALL) NOPASSWD: /usr/sbin/nginx -t
$DEPLOY_USER ALL=(ALL) NOPASSWD: /usr/sbin/nginx -s reload

# supervisor – restrict to horizon workers
$DEPLOY_USER ALL=(ALL) NOPASSWD: /usr/bin/supervisorctl reload
$DEPLOY_USER ALL=(ALL) NOPASSWD: /usr/bin/supervisorctl restart horizon-*
EOF

sudo visudo -cf /etc/sudoers.d/10-deploy || (echo "ERROR in sudoers file" && exit 1)
sudo systemctl daemon-reload
sudo systemctl enable --now deploy-worker.timer
systemctl list-timers --all | grep deploy-worker
