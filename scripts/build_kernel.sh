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
        sudo ./init

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
# Step 3: VM setup — uvt-kvm create ► virsh set MAC ► 固定 IP (DHCP host 条目)
################################################################################
# Preconditions
#   – /local/.tsc_done exists
#   – /local/.vm_setup_done NOT exists
################################################################################
if [ -f "/local/.tsc_done" ] && [ ! -f "/local/.vm_setup_done" ]; then
    step_log "Installing virtualization tools and creating VM (uvt-kvm + static MAC)"

    # 1. Packages
    sudo apt-get update
    sudo apt-get install -y qemu-kvm libvirt-daemon-system libvirt-clients \
                            bridge-utils virtinst uvtool

    # 2. Sync cloud image (once per host)
    step_log "Syncing Ubuntu cloud image"
    sudo uvt-simplestreams-libvirt sync \
         --source https://cloud-images.ubuntu.com/minimal/daily/ \
         release=bionic arch=amd64

    # 3. Names & deterministic IP/MAC
    VM_NAME="ins${INSTANCE_ID}vm"
    INTERNAL_IP="192.168.122.$((4 + INSTANCE_ID))"      # e.g. 4,5,6
    EXPOSED_IP="192.168.1.$((1 + INSTANCE_ID))"         # e.g. 1,2,3
    STATIC_MAC="52:54:00:aa:bb:$(printf '%02x' $((4 + INSTANCE_ID)))"  # 04/05/06

    step_log "VM  = ${VM_NAME}"
    step_log "Int = ${INTERNAL_IP}"
    step_log "MAC = ${STATIC_MAC}"

    # 4. Create VM (uvt-kvm, DHCP 模式即可)
    if ! sudo uvt-kvm create "${VM_NAME}" \
            release=bionic arch=amd64 \
            --cpu 4 --memory 4096 --password 1997; then
        echo "❌ uvt-kvm create failed, aborting"; exit 1
    fi

    # 5. Shut down VM and patch MAC address
    step_log "Shutting VM down to patch MAC"
    sudo virsh shutdown "${VM_NAME}"
    # 等待关机
    for i in {1..20}; do
        state=$(sudo virsh domstate "${VM_NAME}" 2>/dev/null) || true
        [[ "$state" == "shut off" ]] && break
        sleep 1
    done
    if [[ "$state" != "shut off" ]]; then
        echo "❌ VM did not shut off, aborting"; exit 1
    fi

    # 6. Edit XML to set static MAC
    VM_XML="/etc/libvirt/qemu/${VM_NAME}.xml"
    sudo virsh dumpxml "${VM_NAME}" > "${VM_XML}"
    sudo sed -i -E "0,/<mac address='[^']*'/ s//<mac address='${STATIC_MAC}'/" "${VM_XML}"
    sudo virsh define "${VM_XML}"

    # 7. Ensure default network has host entry
    NET_XML="/etc/libvirt/qemu/networks/default.xml"
    if ! grep -q "${STATIC_MAC}" "${NET_XML}"; then
      step_log "Adding DHCP host entry for ${VM_NAME} in default network"
      sudo sed -i -E "/<range /a \\\
      <host mac='${STATIC_MAC}' name='${VM_NAME}' ip='${INTERNAL_IP}'/>" "${NET_XML}"
      sudo virsh net-destroy default
      sudo virsh net-undefine default
      sudo virsh net-define "${NET_XML}"
      sudo virsh net-start  default
      sudo virsh net-autostart default
    fi

    # 8. Start VM
    sudo virsh start "${VM_NAME}"

    # 9. Wait until DHCP assigns the fixed IP
    step_log "Waiting for ${VM_NAME} to get IP ${INTERNAL_IP}"
    for i in {1..30}; do
        cur_ip=$(sudo virsh domifaddr "${VM_NAME}" 2>/dev/null | awk '/ipv4/ {print $4}' | cut -d/ -f1)
        [[ "${cur_ip}" == "${INTERNAL_IP}" ]] && break
        sleep 2
    done
    [[ "${cur_ip}" != "${INTERNAL_IP}" ]] && echo "⚠️  VM IP is ${cur_ip:-N/A}, expected ${INTERNAL_IP}"

    # 10. Done
    touch /local/.vm_setup_done
fi

################################################################################
# Step 4: Exposed-IP alias  &  NAT rules (runs once per host)
################################################################################
# Preconditions
#   – /local/.vm_setup_done   exists  (VM created)
#   – /local/.net_setup_done  NOT     exists (NAT not yet written)
################################################################################
if [ -f "/local/.vm_setup_done" ] && [ ! -f "/local/.net_setup_done" ]; then
    step_log "Setting alias IP and NAT rules for this host"

    # 1. Flush old tables and turn on forwarding
    sudo iptables -F
    sudo iptables -t nat -F
    echo 1 | sudo tee /proc/sys/net/ipv4/ip_forward >/dev/null

    # 2. Find the primary outbound NIC (first 'dev' after default route)
    EXPOSE_IFACE=$(ip route get 1 | awk '{for(i=1;i<=NF;i++) if ($i=="dev"){print $(i+1);exit}}')
    step_log "Outbound interface detected: ${EXPOSE_IFACE}"

    # 3. Parse ip.conf line that matches this host
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    ip_conf="${SCRIPT_DIR}/../config/ip.conf"
    host=$(hostname)
    short_host=${host%%.*}
    line=$(grep "^${short_host}:" "${ip_conf}" || true)
    if [ -z "$line" ]; then
        step_log "❌ No entry for '${short_host}' in ${ip_conf}; skipping NAT setup"
        touch /local/.net_setup_done
        exit 0
    fi

    # 4. Iterate each exposed:internal pair for this host
    echo "$line" | sed -E 's/^[^:]+://g' | tr -d '{}" ' | tr ',' '\n' | while read -r pair; do
        [ -z "$pair" ] && continue
        exposed_ip=${pair%%:*}
        internal_ip=${pair##*:}

        step_log "Alias ${exposed_ip}  →  DNAT to ${internal_ip}"
        sudo ip addr add "${exposed_ip}/24" dev "${EXPOSE_IFACE}" label "${EXPOSE_IFACE}:exposed" || true
        sudo iptables -t nat -A PREROUTING  -d "${exposed_ip}"  -j DNAT --to-destination "${internal_ip}"
        sudo iptables -t nat -A POSTROUTING -s "${internal_ip}" -j MASQUERADE
    done

    # 5. Show final NAT table for verification
    step_log "PREROUTING:"
    sudo iptables -t nat -L PREROUTING  -n
    step_log "POSTROUTING:"
    sudo iptables -t nat -L POSTROUTING -n

    touch /local/.net_setup_done
fi



################################################################################
# Step 5: All done
################################################################################
step_log "All steps already completed. Nothing to do."