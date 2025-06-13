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
MACHINE_NUM="$2"
INSTANCE_ID="$3"
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
fi

################################################################################
# Step 3: VM Setup
################################################################################

if [ -f "/local/.tsc_done" ] && [ ! -f "/local/.vm_setup_done" ]; then
    step_log "Installing virtualization tools and setting up VM"
    # Tool for simplifying the creation of Ubuntu VMs

    sudo apt-get install -y qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils virtinst uvtool
    # Pull image tags
    step_log "Syncing Ubuntu cloud image"
    sudo uvt-simplestreams-libvirt sync --source https://cloud-images.ubuntu.com/minimal/daily/ release=bionic arch=amd64

    VM_NAME="ins${INSTANCE_ID}vm"
    STATIC_IP="192.168.1.$((INSTANCE_ID + 1))"

    step_log "Creating KVM VM named '$VM_NAME'"
    sudo uvt-kvm create "$VM_NAME" release=bionic arch=amd64 --cpu 4 --memory 4096 --password 1997

    step_log "Modifying /etc/libvirt/qemu/$VM_NAME.xml to patch CPU and clock settings"
        VM_XML="/etc/libvirt/qemu/${VM_NAME}.xml"
        TMP_XML="/tmp/${VM_NAME}.xml.modified"

        sudo cp "$VM_XML" "$VM_XML.bak"

        step_log "Deleting two lines after </features>"
        sudo awk '
        /<\/features>/ {
            print;
            skip = 2;
            next;
        }
        skip > 0 {
            skip--;
            next;
        }
        { print }
        ' "$VM_XML" > "$TMP_XML"

        step_log "Inserting new <cpu> and <clock> blocks"
        sudo sed -i "/<\/features>/a \
    <cpu mode='host-passthrough' check='none'>\\
      <feature policy='disable' name='rdtscp'/>\\
      <feature policy='disable' name='tsc-deadline'/>\\
    </cpu>\\
    <clock offset='localtime'>\\
      <timer name='rtc' present='no' tickpolicy='delay'/>\\
      <timer name='pit' present='no' tickpolicy='discard'/>\\
      <timer name='hpet' present='no'/>\\
      <timer name='kvmclock' present='yes'/>\\
    </clock>" "$TMP_XML"

        step_log "Replacing $VM_NAME.xml with modified version and redefining domain"
        sudo mv "$TMP_XML" "$VM_XML"
        sudo virsh define "$VM_XML"

        sudo virsh destroy "$VM_NAME"
        sudo virsh start "$VM_NAME"

        step_log "Assigning fixed alias IP 192.168.1.$((INSTANCE_ID + 1)) for VM"

        step_log "Enabling IP forwarding"
        echo 1 | sudo tee /proc/sys/net/ipv4/ip_forward >/dev/null

        step_log "Waiting for VM $VM_NAME to obtain IP address..."
        VM_IP=""
        for attempt in {1..10}; do
            VM_IP=$(sudo uvt-kvm ip "$VM_NAME")
            if [ -n "$VM_IP" ]; then
                break
            fi
            sleep 2
        done

        if [ -z "$VM_IP" ]; then
            echo "❌ Could not determine IP address for VM $VM_NAME"
        else
            step_log "VM $VM_NAME has IP $VM_IP"
            step_log "Mapping $STATIC_IP to $VM_IP via iptables"

            # Optional: Add host alias IP to virbr0 for local access
            sudo ip addr add "$STATIC_IP/24" dev virbr0 || true

            # NAT rules
            sudo iptables -t nat -A PREROUTING -d "$STATIC_IP" -j DNAT --to-destination "$VM_IP"
            sudo iptables -t nat -A POSTROUTING -s "$VM_IP" -j MASQUERADE
        fi



    touch /local/.vm_setup_done
    exit 0
fi

################################################################################
# Step 4: All done
################################################################################

step_log "All steps already completed. Nothing to do."