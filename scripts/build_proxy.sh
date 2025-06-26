#!/bin/bash
exec >> /local/build.log
exec 2>&1
# Color output
GREEN=$'\033[0;32m'
BLUE=$'\033[0;34m'
NC=$'\033[0m'
if ! test -t 1; then
    GREEN=""
    BLUE=""
    NC=""
fi

function step_log() {
    echo ""
    echo "====================[ $1 ]===================="
    date
    if [ -n "$2" ]; then
        echo ""
        echo "$2"
    fi
    echo ""
}
GITHUB_TOKEN="$1"
GITHUB_USERNAME="ujjwalpawar"
kernel_repo="andrewferguson/phobos-proxy"
  sudo apt update 
  sudo apt-get install -yqq libsctp-dev lksctp-tools  zlib1g-dev
  sudo modprobe sctp
phobos_link="https://${GITHUB_USERNAME}:${GITHUB_TOKEN}@github.com/${kernel_repo}.git"
git clone --quiet "${phobos_link}" ~/phobos-proxy
cd ~/phobos-proxy
make -j
