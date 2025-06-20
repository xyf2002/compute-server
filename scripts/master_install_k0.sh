#!/usr/bin/env bash
set -euo pipefail
LOG_FILE="/home/ubuntu/k0s_master.log"
source /tmp/common.sh

install_deps
install_k0s

log "Installing controller service"
k0s config create > k0s.yaml
sudo k0s install controller -c k0s.yaml --enable-worker
sudo k0s start
sudo k0s token create --role=worker --expiry=100h > /home/ubuntu/token-file
sudo systemctl enable --now k0scontroller

#Generate and save Worker token
log "Worker join-token written to /home/ubuntu/token-file
