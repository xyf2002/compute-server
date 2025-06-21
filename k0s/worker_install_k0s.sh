#!/usr/bin/env bash
# Usage: sudo ./worker_install_k0s.sh <controller_ip>
set -euo pipefail
CTL_IP=${1:? "❌ Controller IP required as argument"}
LOG_FILE="/tmp/k0s_worker.log"

source /tmp/common.sh

log "========== [Worker Node Setup Started] =========="
log "Connecting to controller at ${CTL_IP}"

install_deps
log "✅ Dependencies installed"

install_k0s
log "✅ k0s installed"

log "Waiting to fetch join token from controller..."
TOKEN=$(wait_for_token "$CTL_IP") || fail "❌ Could not fetch token from $CTL_IP"

log "✅ Token fetched successfully"
log "🔑 Token preview: ${TOKEN:0:16}..."

log "Installing worker service with token..."
sudo k0s install worker --token "$TOKEN" >>"$LOG_FILE"

log "Enabling and starting k0sworker systemd service..."
sudo systemctl enable --now k0sworker

log "✅ Worker service installed and started"
log "========== [Worker Node Setup Complete] =========="
