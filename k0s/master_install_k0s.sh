#!/usr/bin/env bash
set -euo pipefail
LOG_FILE="/tmp/k0s_master.log"
source /tmp/common.sh

log "========== [Master Node Setup Started] =========="

install_deps
log "✅ Dependencies installed"

install_k0s
log "✅ k0s installed"

log "Installing controller service..."
sudo k0s install controller >>"$LOG_FILE"
log "✅ Controller service installed"

log "Enabling and starting k0scontroller systemd service..."
sudo systemctl enable --now k0scontroller

log "Waiting for k0scontroller to start..."
for i in {1..30}; do
    if sudo k0s status &>/dev/null; then
        log "✅ k0scontroller is running"
        break
    fi
    sleep 2
done
if ! sudo k0s status &>/dev/null; then
    fail "❌ k0scontroller failed to start after waiting"
fi

# Generate and save Worker token
log "Generating join token for worker..."
CTL_IP="192.168.10.2"
TOKEN=$(sudo k0s token create --role=worker)
echo "$TOKEN" | sudo tee /tmp/worker.token >/dev/null

log "✅ Worker join-token written to /local/worker.token"
log "🔑 Token preview: ${TOKEN:0:16}..."

log "========== [Master Node Setup Complete] =========="
