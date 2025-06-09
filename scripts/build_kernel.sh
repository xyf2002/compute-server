#!/bin/bash

# Build and install a custom Linux kernel
# This replicates the steps used in the Azure/GCP setup.

set -e

REPO_URL="https://github.com/torvalds/linux.git"
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
sudo apt-get install -y build-essential git libncurses-dev bison flex libssl-dev libelf-dev

# Fetch sources
rm -rf "$SRC_DIR"
git clone --depth 1 --branch "$BRANCH" "$REPO_URL" "$SRC_DIR"
cd "$SRC_DIR"

# Configure and build
make olddefconfig
make -j"$(nproc)"

# Install
sudo make modules_install
sudo make install
sudo update-grub

# Leave sources in place for inspection

echo "Kernel build complete"

