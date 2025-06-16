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
# Step 3: VM setup & dynamic IP mapping via ip.conf
################################################################################
# Preconditions:
#   - /local/.tsc_done exists
#   - /local/.vm_setup_done NOT exists
################################################################################
if [ -f "/local/.tsc_done" ] && [ ! -f "/local/.vm_setup_done" ]; then
    step_log "Installing virtualization tools and setting up VM"

    # -------------------------------------------------------------------------
    # 1. Install KVM / libvirt / uvtool
    # -------------------------------------------------------------------------
    sudo apt-get update
    sudo apt-get install -y qemu-kvm libvirt-daemon-system libvirt-clients \
                            bridge-utils virtinst uvtool

    # -------------------------------------------------------------------------
    # 2. Download Ubuntu Cloud image
    # -------------------------------------------------------------------------
    step_log "Syncing Ubuntu cloud image"
    sudo uvt-simplestreams-libvirt sync \
         --source https://cloud-images.ubuntu.com/minimal/daily/ \
         release=bionic arch=amd64

    # -------------------------------------------------------------------------
    # 3. Create VM
    # -------------------------------------------------------------------------
    VM_NAME="ins${INSTANCE_ID}vm"
    step_log "Creating KVM VM named '$VM_NAME'"
    sudo uvt-kvm create "$VM_NAME" \
         release=bionic arch=amd64 \
         --cpu 4 --memory 4096 --password 1997

    # -------------------------------------------------------------------------
    # 4. Patch CPU / clock model in VM XML
    # -------------------------------------------------------------------------
    VM_XML="/etc/libvirt/qemu/${VM_NAME}.xml"
    TMP_XML="/tmp/${VM_NAME}.xml.modified"
    sudo cp "$VM_XML" "$VM_XML.bak"

    step_log "Deleting two lines after </features>"
    sudo awk '
        /<\/features>/ { print; skip=2; next }
        skip>0 { skip--; next }
        { print }
    ' "$VM_XML" > "$TMP_XML"

    step_log "Inserting new <cpu> and <clock> blocks"
    sudo sed -i "/<\/features>/a \
    <cpu mode='host-passthrough' check='none'>\\
      <feature policy='disable' name='rdtscp'/>\\
      <feature policy='disable' name='tsc-deadline'/>\\
    </cpu>\\
    <clock offset='localtime'>\\
      <timer name='rtc'  present='no' tickpolicy='delay'/>\\
      <timer name='pit'  present='no' tickpolicy='discard'/>\\
      <timer name='hpet' present='no'/>\\
      <timer name='kvmclock' present='yes'/>\\
    </clock>" "$TMP_XML"

    step_log "Redefining domain with patched XML"
    sudo mv "$TMP_XML" "$VM_XML"
    sudo virsh define "$VM_XML"
    sudo virsh destroy "$VM_NAME" || true
    sudo virsh start "$VM_NAME"

    # -------------------------------------------------------------------------
    # 5. Enable IP forwarding & flush old iptables rules
    # -------------------------------------------------------------------------
    step_log "Enabling IP forwarding + flushing iptables"
    sudo iptables -F
    sudo iptables -t nat -F
    echo 1 | sudo tee /proc/sys/net/ipv4/ip_forward >/dev/null

    # Basic open rules (optional)
    sudo iptables -A INPUT   -p udp  -j ACCEPT
    sudo iptables -A OUTPUT  -p udp  -j ACCEPT
    sudo iptables -A FORWARD -p tcp  -j ACCEPT
    sudo iptables -A OUTPUT  -p tcp  -j ACCEPT

    # -------------------------------------------------------------------------
    # 6. Wait for VM to obtain a virbr0 DHCP address
    # -------------------------------------------------------------------------
    step_log "Waiting for VM '$VM_NAME' to obtain IP address..."
    VM_IP=""
    for attempt in {1..10}; do
        VM_IP=$(sudo uvt-kvm ip "$VM_NAME")
        [[ -n "$VM_IP" ]] && break
        sleep 2
    done
    [[ -z "$VM_IP" ]] && { echo "❌ Could not determine VM IP"; exit 1; }
    step_log "VM '$VM_NAME' has IP $VM_IP"

    # -------------------------------------------------------------------------
    # 7. Determine host physical interface to hold exposed IP aliases
    # -------------------------------------------------------------------------
    # AUTO-DETECT default-route interface; override manually if needed
    EXPOSED_IFACE=$(ip -o -4 route get 1 | awk '{print $5; exit}')
    step_log "Using interface '$EXPOSED_IFACE' for exposed IP aliases"

    # -------------------------------------------------------------------------
    # 8. Parse ip.conf and add DNAT/SNAT rules (current node only)
    # -------------------------------------------------------------------------
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    ip_conf="${SCRIPT_DIR}/../config/ip.conf"
    current_hostname=$(hostname)

    step_log "Applying iptables rules based on ${ip_conf}"
    grep "^${current_hostname}:" "$ip_conf" | while read -r line; do
        ip_pair=$(echo "$line" | sed -E 's/^[^:]+://g' | tr -d '{}" ')
        echo "$ip_pair" | tr ',' '\n' | while read -r pair; do
            [[ -z "$pair" || ! "$pair" =~ ":" ]] && continue
            exposed_ip=$(echo "$pair" | cut -d':' -f1)   # e.g. 192.168.1.1
            internal_ip=$(echo "$pair" | cut -d':' -f2)  # e.g. 192.168.122.5

            step_log "DNAT ${exposed_ip} -> ${internal_ip}  (alias on ${EXPOSED_IFACE})"
            sudo ip addr add "${exposed_ip}/24" dev "${EXPOSED_IFACE}" || true
            sudo iptables -t nat -A PREROUTING  -d "${exposed_ip}" -j DNAT --to-destination "${internal_ip}"
            sudo iptables -t nat -A POSTROUTING -s "${internal_ip}" -j MASQUERADE
        done
    done

    step_log "Dynamic IP mapping completed"

    # -------------------------------------------------------------------------
    # 9. Mark completion flag and exit
    # -------------------------------------------------------------------------
    touch /local/.vm_setup_done
    exit 0
fi

################################################################################
# Step 4: All done
################################################################################
step_log "All steps already completed. Nothing to do."

################################################################################
# Step 4: All done
################################################################################
step_log "All steps already completed. Nothing to do."