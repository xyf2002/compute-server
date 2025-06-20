#!/usr/bin/env bash
set -euo pipefail
LOG_FILE="/local/k0s_master.log"
source /local/repository/k0s/common.sh

install_deps
install_k0s

log "Installing controller service"
sudo k0s install controller >>"$LOG_FILE"
sudo systemctl enable --now k0scontroller

#Generate and save Worker token
CTL_IP="192.168.1.1"
TOKEN=$(sudo k0s token create --role=worker --api-url "https://${CTL_IP}:6443")
echo "$TOKEN" | sudo tee /local/worker.token >/dev/null
log "Worker join-token written to /local/worker.token"