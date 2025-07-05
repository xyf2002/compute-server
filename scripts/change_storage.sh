#!/usr/bin/env bash
#
# change-uvtool-pool.sh
# Relocates the “uvtool” libvirt storage pool to /storage/uvtool
# and ensures every future image is owned by libvirt-qemu:kvm
# ------------------------------------------------------------------
set -euo pipefail

POOL_NAME="uvtool"
NEW_PATH="/storage/uvtool"
XML_TMP="/tmp/${POOL_NAME}.xml"

# User / group to own the pool contents
POOL_USER="libvirt-qemu"
POOL_GROUP="kvm"
POOL_UID=$(id -u "$POOL_USER")
POOL_GID=$(getent group "$POOL_GROUP" | cut -d: -f3)

echo "🔍 Checking that the pool exists…"
if ! sudo virsh pool-info "$POOL_NAME" &>/dev/null; then
  echo "❌ Pool \"$POOL_NAME\" not found. Aborting." >&2
  exit 1
fi

echo "📦 Stopping the pool (harmless if already inactive)…"
sudo virsh pool-destroy "$POOL_NAME" || true

echo "📂 Creating new target directory $NEW_PATH"
sudo mkdir -p "$NEW_PATH"

echo "🔑 Fixing directory ownership, setgid & default ACL"
sudo chown -R "${POOL_USER}:${POOL_GROUP}" "$NEW_PATH"
sudo chmod 2770 "$NEW_PATH"                              # setgid so new files inherit group=kvm
sudo setfacl -d -m "g:${POOL_GROUP}:rwx" "$NEW_PATH"     # default ACL for safety

echo "📝 Re-defining the pool with explicit permissions…"
cat >"$XML_TMP" <<EOF
<pool type='dir'>
  <name>${POOL_NAME}</name>
  <target>
    <path>${NEW_PATH}</path>
    <permissions>
      <mode>0770</mode>
      <owner>${POOL_UID}</owner>
      <group>${POOL_GID}</group>
    </permissions>
  </target>
</pool>
EOF

echo "🧹 Removing old pool definition"
sudo virsh pool-undefine "$POOL_NAME"

echo "➕ Defining new pool"
sudo virsh pool-define "$XML_TMP"

echo "🔧 Building and starting the pool…"
sudo virsh pool-build      "$POOL_NAME"
sudo virsh pool-start      "$POOL_NAME"
sudo virsh pool-autostart  "$POOL_NAME"

echo "✅ Pool \"$POOL_NAME\" now points to $NEW_PATH with enforced permissions"

echo "👉 If you still have volumes in the old location, move them and re-apply ownership:"
echo "   sudo rsync -a /var/lib/uvtool/libvirt/images/ \"${NEW_PATH}/\""
echo "   sudo chown -R ${POOL_USER}:${POOL_GROUP} \"${NEW_PATH}\""

echo "🐧 AppArmor users (Ubuntu):"
echo "   echo \"/storage/uvtool/** rwk,\" | sudo tee /etc/apparmor.d/local/abstractions/libvirt-qemu"
echo "   sudo systemctl reload apparmor"
