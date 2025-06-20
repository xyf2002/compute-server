#!/usr/bin/env bash
# Usage: sudo ./worker_install_k0s.sh <controller_ip>
set -euo pipefail
CTL_IP=${1:? "controller IP required"}
LOG_FILE="/home/ubuntu/k0s_worker.log"
source /tmp/common.sh

install_deps
install_k0s

TOKEN=$(wait_for_token "$CTL_IP") || fail "Could not fetch token"
log "Joining cluster with token"
sudo k0s install worker --token "$TOKEN" >>"$LOG_FILE"
sudo systemctl enable --now k0sworker
