#!/bin/bash

# Build and install a custom Linux kernel
set -e

REPO_URL="https://github.com/ujjwalpawar/chronos-kernel"
BRANCH="master"
SRC_DIR="/tmp/linux-src"

# Allow arguments to override repository, branch or other options
while [ $# -gt 0 ]; do
    case "$1" in
        --repo)
            REPO_URL="$2"; shift 2;;
        --branch)
            BRANCH="$2"; shift 2;;
        *)
            break;;
    esac
done


# Install dependencies
sudo apt-get update
cd chronos-kernel
sudo apt-get install -y build-essential git libncurses-dev bison flex libssl-dev libelf-dev dwarves ripgrep


# Fetch sources
rm -rf "$SRC_DIR"
git clone --depth 1 --branch "$BRANCH" "$REPO_URL" "$SRC_DIR"
cd "$SRC_DIR"

# Configure kernel based on current running config
cp -v /boot/config-$(uname -r) .config
scripts/config --disable SYSTEM_TRUSTED_KEYS

scripts/config --disable SYSTEM_REVOCATION_KEYS
scripts/config --set-val CONFIG_DEBUG_INFO_BTF n

make olddefconfig
make -j"$(nproc)"

# Install
sudo make INSTALL_MOD_STRIP=1 modules_install
sudo make install
sudo update-grub

# Leave sources in place for inspection

echo "Kernel build complete"

