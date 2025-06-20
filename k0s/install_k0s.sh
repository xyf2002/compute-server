#!/usr/bin/env bash
#
# Usage:
#   sudo ./install_k0s.sh                 # single-node all-in-one
#   sudo ./install_k0s.sh controller      # controller only
#   sudo ./install_k0s.sh worker <TOKEN>  # worker node, requires join-token from controller
#
set -euo pipefail

ROLE=${1:-single}     # single (default) | controller | worker
TOKEN=${2:-""}

echo "[*] Installing prerequisites ..."
sudo apt-get update -qq
sudo apt-get install -yqq curl conntrack socat ebtables iptables >/dev/null

echo "[*] Downloading and installing the latest stable k0s ..."
# Official script drops the binary into /usr/local/bin
curl -sSLf https://get.k0s.sh | sudo bash

case "$ROLE" in
  single)
    echo "[*] Single-node mode: controller + worker on the same box"
    sudo k0s install controller --single           # installs as a systemd service
    sudo systemctl enable --now k0scontroller
    ;;
  controller)
    echo "[*] Controller mode"
    sudo k0s install controller
    sudo systemctl enable --now k0scontroller

    echo
    echo "✓ Controller is up. Generate a worker join token with:"
    sudo k0s token create --role=worker
    echo "(Copy the full token line above to each worker node.)"
    ;;
  worker)
    if [[ -z "$TOKEN" ]]; then
      echo "✗ Worker mode requires a join token!"
      exit 1
    fi
    echo "[*] Worker mode: joining the cluster with provided token"
    sudo k0s install worker --token "$TOKEN"
    sudo systemctl enable --now k0sworker
    ;;
  *)
    echo "Usage: $0 [single|controller|worker <join-token>]"
    exit 1
    ;;
esac

echo
sudo k0s status        # Show service status