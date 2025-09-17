#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && cd .. && pwd )"

source "$BASE_DIR/.env"

composer install --no-interaction --prefer-dist --optimize-autoloader --no-dev --no-scripts --no-ansi

cat <<EOF | sudo tee /etc/systemd/system/deploy-worker.service
[Unit]
Description=Deploy Worker Job
After=network.target

[Service]
Type=oneshot
User=$USER
Group=$USER
ExecStart=$BASE_DIR/bin/deploy-worker
WorkingDirectory=$BASE_DIR
EOF

cat <<EOF | sudo tee /etc/systemd/system/deploy-worker.timer
[Unit]
Description=Run Deploy Worker every 10 seconds

[Timer]
# Start 10 seconds after boot
OnBootSec=10s
# Repeat every 10 seconds after the service finishes
OnUnitActiveSec=10s
Unit=deploy-worker.service
Persistent=true

[Install]
WantedBy=timers.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now deploy-worker.timer

