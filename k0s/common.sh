#!/usr/bin/env bash
# shellcheck disable=SC1091
set -euo pipefail

# =========================
# Global Config
# =========================
K0S_VERSION_CHANNEL="stable"
K0S_BIN="/usr/local/bin/k0s"
LOG_FILE="/tmp/k0s_master.log"

SSH_USER="ubuntu"
SSH_PASS="1997"
SSH_OPTS="-oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null"

# =========================
# Logging Functions
# =========================
log()  { echo -e "[\e[34mINFO\e[0m] $*" | tee -a "$LOG_FILE"; }
fail() { echo -e "[\e[31mFAIL\e[0m] $*" | tee -a "$LOG_FILE"; exit 1; }

# =========================
# Prerequisite Installation
# =========================
install_deps() {
  log "Installing prerequisites"
  sudo apt-get update -qq
  sudo apt-get install -yqq curl conntrack socat ebtables iptables sshpass >>"$LOG_FILE"

  # Install sshpass if not available
    if ! command -v sshpass >/dev/null 2>&1; then
      log "Installing sshpass"
      sudo apt-get install -y sshpass >>"$LOG_FILE"
    fi


  log "Installing Helm"
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash >>"$LOG_FILE"

  # Verify Helm installation
  if command -v helm >/dev/null 2>&1; then
    log "Helm version: $(helm version --short)"
  else
    fail "Helm installation failed: helm command not found"
  fi
}

# =========================
# k0s Installation
# =========================
install_k0s() {
  log "Downloading k0s installer script"
  curl -fsSL https://get.k0s.sh -o /tmp/get-k0s.sh
  chmod +x /tmp/get-k0s.sh

  log "Running k0s installer"
  sudo /tmp/get-k0s.sh "$K0S_VERSION_CHANNEL" >>"$LOG_FILE" 2>&1

  if [ -x "$K0S_BIN" ]; then
    log "k0s version: $($K0S_BIN version)"
  else
    ls -l /usr/local/bin >>"$LOG_FILE"
    fail "k0s installation failed: $K0S_BIN not found or not executable"
  fi
}

# =========================
# Wait for Join Token
# =========================
wait_for_token() {         # $1 = controller_ip
  local ctl_ip=$1
  local token=""
  log "Waiting for join token from $ctl_ip ..."
  for _ in {1..60}; do
    token=$(sshpass -p "$SSH_PASS" ssh $SSH_OPTS "$SSH_USER@$ctl_ip" cat /local/worker.token 2>/dev/null || true)
    [[ -n "$token" ]] && { echo "$token"; return 0; }
    sleep 5
  done
  fail "Timed out waiting for join token from $ctl_ip"
}
