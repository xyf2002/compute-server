#!/usr/bin/env bash
set -euo pipefail
LOG_FILE="/home/ubuntu/k0s_master.log"
source /tmp/common_k0.sh

install_deps
install_k0s

log "Installing controller service"
k0s config create > k0s.yaml
sudo k0s install controller -c k0s.yaml --enable-worker
sudo k0s start

dest=/home/ubuntu/token-file   # final location
delay=5                        # seconds between attempts

while :; do
  echo "⇒ Requesting worker token …"
  token=$(sudo k0s token create --role=worker --expiry=100h || true)

  if [[ -n $token ]]; then           # non-empty?
    printf '%s\n' "$token" > "$dest"
    echo "✓ Token saved to $dest"
    break
  else
    echo "⚠️  k0s returned an empty token; retrying in $delay s …"
    sleep "$delay"
  fi
done

#Generate and save Worker token
log "Worker join-token written to /home/ubuntu/token-file
