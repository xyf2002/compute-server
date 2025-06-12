#!/bin/bash
# Builds the kernel from source, installs it, and builds the fake_tsc module after reboot

# Redirect output to log file
exec >> /local/build.log
exec 2>&1

# Color
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
USER_HOME="/users/$(whoami)"

kernel_repo="ujjwalpawar/chronos-kernel"
tsc_repo="ujjwalpawar/fake_tsc"
kernel_link="https://${GITHUB_USERNAME}:${GITHUB_TOKEN}@github.com/${kernel_repo}.git"
tsc_link="https://${GITHUB_USERNAME}:${GITHUB_TOKEN}@github.com/${tsc_repo}.git"

################################################################################
# After Reboot: Build and Insert fake_tsc
################################################################################

#if [ -f "/local/.rebooted" ]; then
#    step_log "After reboot: building and inserting fake_tsc module"
#    rm -f /local/.rebooted
#
#    cd "${USER_HOME}"
#    if [ ! -d "fake_tsc" ]; then
#        git clone "${tsc_link}" fake_tsc
#    fi
#    cd fake_tsc
#    make
#    sudo insmod custom_tsc.ko
#
#    step_log "fake_tsc module inserted"
#    lsmod | grep custom_tsc || echo "⚠️ Warning: custom_tsc not in lsmod"
#    dmesg | tail -n 20
#
#    exit 0
#fi

################################################################################
# Kernel Build: First Boot
################################################################################

step_log "Installing kernel build dependencies"
sudo apt-get update
sudo apt-get install -y build-essential git libncurses-dev bison flex libssl-dev libelf-dev dwarves ripgrep

step_log "Cloning kernel repo to ~/chronos-kernel"
git clone --quiet "${kernel_link}" "${USER_HOME}/chronos-kernel"
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
make -j"$(nproc)"

step_log "Installing kernel modules"
sudo make INSTALL_MOD_STRIP=1 modules_install
sudo make install

step_log "Updating grub"
sudo update-grub

step_log "Cloning fake_tsc repo"
cd "${USER_HOME}"
if [ ! -d "fake_tsc" ]; then
    git clone "${tsc_link}" fake_tsc
fi

################################################################################
# Finish: Trigger Reboot
################################################################################

step_log "Kernel build complete, reboot required"
touch /local/.rebooted
sudo reboot
