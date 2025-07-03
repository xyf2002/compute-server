#!/usr/bin/env bash
#
# change-uvtool-pool.sh
# Relocates the “uvtool” libvirt storage pool to /storage/uvtool and sets up AppArmor-safe symlink
# ------------------------------------------------------------------
set -euo pipefail

POOL_NAME="uvtool"
NEW_PATH="/storage/uvtool"
LINK_PATH="/var/lib/uvtool/libvirt/images"
XML_TMP="/tmp/${POOL_NAME}.xml"

echo "🔍 Checking that the pool exists…"
if ! sudo virsh pool-info "$POOL_NAME" &>/dev/null; then
  echo "❌ Pool \"$POOL_NAME\" not found. Creating it fresh."
  sudo mkdir -p "$LINK_PATH"
  sudo virsh pool-define-as "$POOL_NAME" dir - - - - "$LINK_PATH"
fi

echo "📦 Stopping the pool (harmless if already inactive)…"
sudo virsh pool-destroy "$POOL_NAME" || true

echo "📂 Creating target directory $NEW_PATH"
sudo mkdir -p "$NEW_PATH"
sudo chmod 755 /storage
sudo chown -R libvirt-qemu:kvm "$NEW_PATH"
sudo chmod -R 755 "$NEW_PATH"

echo "🔄 Migrating old images (if any)..."
if [ -d "/var/lib/uvtool/libvirt/images" ] && [ ! -L "$LINK_PATH" ]; then
  sudo rsync -a /var/lib/uvtool/libvirt/images/ "$NEW_PATH/"
fi

echo "🔗 Creating symlink to bypass AppArmor restrictions..."
sudo rm -rf "$LINK_PATH"
sudo ln -s "$NEW_PATH" "$LINK_PATH"

echo "📝 Re-defining the pool with symlink-safe path..."
cat >"$XML_TMP" <<EOF
<pool type='dir'>
  <name>${POOL_NAME}</name>
  <target>
    <path>${LINK_PATH}</path>
  </target>
</pool>
EOF

sudo virsh pool-undefine "$POOL_NAME" || true
sudo virsh pool-define "$XML_TMP"

echo "🔧 Building and starting the pool…"
sudo virsh pool-build "$POOL_NAME"
sudo virsh pool-start "$POOL_NAME"
sudo virsh pool-autostart "$POOL_NAME"

echo "✅ Pool \"$POOL_NAME\" now points to $NEW_PATH (via symlink)"
