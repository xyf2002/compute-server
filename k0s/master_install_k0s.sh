#!/usr/bin/env bash
set -euo pipefail
LOG_FILE="/tmp/k0s_master.log"
source /tmp/common.sh

install_deps
install_k0s

log "Installing controller service"
sudo k0s install controller >>"$LOG_FILE"
sudo systemctl enable --now k0scontroller

#Generate and save Worker token
CTL_IP="192.168.10.2"
TOKEN=$(sudo k0s token create --role=worker)
echo "$TOKEN" | sudo tee /local/worker.token >/dev/null
log "Worker join-token written to /local/worker.token"