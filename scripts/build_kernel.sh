#!/bin/bash
# Builds the kernel from source, installs it, and builds the fake_tsc module after reboot

# Redirect output to log file
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
# Step 1: Kernel Build
################################################################################

if [ ! -f "/local/.kernel_done" ]; then
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

    step_log "Mark kernel done and reboot"
    touch /local/.kernel_done
    touch /local/.rebooted
    sudo reboot
    exit 0
fi

################################################################################
# Step 2: After Reboot, build & insert fake_tsc
################################################################################

if [ -f "/local/.kernel_done" ] && [ -f "/local/.rebooted" ] && [ ! -f "/local/.tsc_done" ]; then
    step_log "After reboot: building and inserting fake_tsc module"
    rm -f /local/.rebooted

    cd "${USER_HOME}"
    if [ ! -d "fake_tsc" ]; then
        git clone "${tsc_link}" fake_tsc
    fi
    cd fake_tsc

    if [ -f init.c ]; then
            step_log "Compiling and running init.c"
            gcc init.c -o init
            sudo ./init
    fi

    if [ -f shared.c ]; then
        step_log "Compiling shared.c"
        gcc shared.c -o shared
    fi

    step_log "Building fake_tsc module"
    make

    step_log "Unloading existing KVM modules (if any)"
        sudo rmmod kvm_intel || true
        sudo rmmod kvm || true

    step_log "Inserting custom_tsc.ko"
    sudo insmod custom_tsc.ko
    sudo modprobe kvm
    sudo modprobe kvm_intel

    step_log "Re-loading KVM modules"

    step_log "fake_tsc module inserted"
    lsmod | grep custom_tsc || echo "⚠️ Warning: custom_tsc not in lsmod"
    dmesg | tail -n 20

    touch /local/.tsc_done
    exit 0
fi

################################################################################
# Step 3: VM Setup
################################################################################

if [ -f "/local/.tsc_done" ] && [ ! -f "/local/.vm_setup_done" ]; then
    step_log "Installing virtualization tools and setting up VM"
    # Tool for simplifying the creation of Ubuntu VMs
    sudo apt-get install -y qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils virtinst uvtool
    # Pull image tags
    sudo uvt-simplestreams-libvirt sync --source https://cloud-images.ubuntu.com/minimal/daily/ release=bionic arch=amd64

    step_log "Creating KVM VM named 'vm'"
    sudo uvt-kvm create vm release=bionic arch=amd64 --cpu 4 --memory 4096 --password 1997

    touch /local/.vm_setup_done
    exit 0
fi

################################################################################
# Step 4: All done
################################################################################

step_log "All steps already completed. Nothing to do."