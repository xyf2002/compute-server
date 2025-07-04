#!/usr/bin/env bash
#
# change-uvtool-pool.sh
# Relocates the “uvtool” libvirt storage pool to /storage/uvtool
# ------------------------------------------------------------------
set -euo pipefail

POOL_NAME="uvtool"
NEW_PATH="/storage/uvtool"
XML_TMP="/tmp/${POOL_NAME}.xml"
POOL_USER="libvirt-qemu"
POOL_GROUP="kvm"

echo "🔍 Checking that the pool exists…"
if ! sudo virsh pool-info "$POOL_NAME" &>/dev/null; then
  echo "❌ Pool \"$POOL_NAME\" not found. Aborting." >&2
  exit 1
fi

echo "📦 Stopping the pool (harmless if already inactive)…"
sudo virsh pool-destroy "$POOL_NAME" || true

echo "📂 Creating new target directory $NEW_PATH"
sudo mkdir -p "$NEW_PATH"

echo "🔑 Setting ownership to ${POOL_USER}:${POOL_GROUP}"
sudo chown -R "${POOL_USER}:${POOL_GROUP}" "$NEW_PATH"
# If you prefer tighter permissions, uncomment the next line:
# sudo chmod 770 "$NEW_PATH"

echo "📝 Re-defining the pool with the new path…"
cat >"$XML_TMP" <<EOF
<pool type='dir'>
  <name>${POOL_NAME}</name>
  <target>
    <path>${NEW_PATH}</path>
  </target>
</pool>
EOF

echo "🧹 Removing old pool definition"
sudo virsh pool-undefine "$POOL_NAME"

echo "➕ Defining new pool"
sudo virsh pool-define "$XML_TMP"

echo "🔧 Building and starting the pool…"
sudo virsh pool-build     "$POOL_NAME"
sudo virsh pool-start     "$POOL_NAME"
sudo virsh pool-autostart "$POOL_NAME"

echo "✅ Pool \"$POOL_NAME\" now points to $NEW_PATH"
echo "👉 Remember to move any existing volume files, then fix ownership recursively:"
echo "   sudo rsync -a /var/lib/uvtool/libvirt/images/  \"${NEW_PATH}/\""
echo "   sudo chown -R ${POOL_USER}:${POOL_GROUP} \"${NEW_PATH}\""

# Optional: On SELinux-enforcing systems run:
# sudo restorecon -Rv "${NEW_PATH}"
