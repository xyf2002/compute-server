#!/bin/bash
# Builds the kernel from source, installs it, and also builds the custom
# Chronos kernel module for the same version. Finally, creates two QEMU VMs
# and configures them for Chronos.

# Redirect output to log file
exec >> /local/build.log
exec 2>&1

# Color (disable if not a TTY)
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
    echo ""
}

GITHUB_TOKEN="$1"
GITHUB_USERNAME="xyf2002"

if [ -z "$GITHUB_TOKEN" ]; then
    echo "Error: GitHub token not provided. Usage: ./build_kernel.sh <token>"
    exit 1
fi

kernel_repo="ujjwalpawar/chronos-kernel"
tsc_repo="ujjwalpawar/fake_tsc"
kernel_link="https://${GITHUB_USERNAME}:${GITHUB_TOKEN}@github.com/${kernel_repo}.git"
tsc_link="https://${GITHUB_USERNAME}:${GITHUB_TOKEN}@github.com/${tsc_repo}.git"

################################################################################
# Kernel Build
################################################################################

if [ -f "/local/.rebooted" ]; then
    # Configurations that are required after rebooting
    echo "Executing after-reboot configurations"

    echo "Done!"
    date
    touch /local/.rebooted
    echo "Rebooting..."
    exit 0
fi

step_log "Installing kernel build dependencies"
sudo apt-get update
sudo apt-get install -y build-essential git libncurses-dev bison flex libssl-dev libelf-dev dwarves ripgrep

step_log "Cloning kernel repo to home directory"
USER_HOME="/users/$(whoami)"
GIT_TERMINAL_PROMPT=0 git clone --quiet "${kernel_link}" "${USER_HOME}/chronos-kernel"
cd "${USER_HOME}/chronos-kernel"

step_log "Copying current kernel config to .config"
cp "/boot/config-$(uname -r)" .config

step_log "Disabling/enabling kernel config options"
scripts/config --disable SYSTEM_TRUSTED_KEYS
scripts/config --disable SYSTEM_REVOCATION_KEYS
scripts/config --disable VIDEO_OV01A10
scripts/config --enable NETFILTER_XTABLES
scripts/config --enable NETFILTER_XT_MARK
scripts/config --enable NETFILTER_XT_TARGET_MARK
scripts/config --enable PREEMPT_RT_FULL
scripts/config --disable DEBUG_INFO_BTF

step_log "Running olddefconfig"
make olddefconfig

step_log "Building the kernel"
make "-j$(nproc)"

step_log "Installing kernel modules"
sudo make INSTALL_MOD_STRIP=1 modules_install
sudo make install

step_log "Updating grub"
sudo update-grub

################################################################################
# Finish
################################################################################

step_log "Kernel build complete"
touch /local/.rebooted

if [ ! -f "/local/.noreboot" ]; then
    step_log "Rebooting to apply new kernel"
    sudo reboot
fi