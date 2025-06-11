#!/bin/bash
set -e

VERSION="5.15.160+"
ARCHIVE="chronos-kernel-backup-${VERSION}.tar.gz"
RELEASE_URL="https://github.com/xyf2002/compute-server/releases/download/image"
LOG_DIR="/local/logs"
DOWNLOAD_DIR="${HOME}" # Set download directory to user's home directory

# Create log directory if it doesn't exist
mkdir -p "${LOG_DIR}"

# Redirect all output to a log file within the specified directory
exec > >(tee "${LOG_DIR}/kernel_install_$(date +%Y%m%d_%H%M%S).log") 2>&1

echo "[+] Downloading kernel archive to ${DOWNLOAD_DIR}..."
wget -P "${DOWNLOAD_DIR}" "${RELEASE_URL}/${ARCHIVE}"

echo "[+] Extracting..."
tar -xzf "${DOWNLOAD_DIR}/${ARCHIVE}" -C "${DOWNLOAD_DIR}"

KERNEL_DIR="${DOWNLOAD_DIR}/chronos-kernel-backup"

echo "[+] Copying kernel files to /boot and /lib/modules..."
sudo cp "${KERNEL_DIR}/vmlinuz-${VERSION}" /boot/
sudo cp "${KERNEL_DIR}/initrd.img-${VERSION}" /boot/
sudo cp "${KERNEL_DIR}/System.map-${VERSION}" /boot/
sudo cp "${KERNEL_DIR}/config-${VERSION}" /boot/
sudo cp -r "${KERNEL_DIR}/modules/${VERSION}" /lib/modules/

echo "[+] Updating GRUB..."
sudo update-grub

echo "[+] Requesting safe reboot after profile setup..."
sudo reboot

echo "[+] Script finished successfully!"