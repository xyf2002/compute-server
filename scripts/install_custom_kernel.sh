#!/bin/bash
set -e

VERSION=5.15.160+
ARCHIVE=chronos-kernel-backup-${VERSION}.tar.gz
RELEASE_URL=https://github.com/xyf2002/compute-server/releases/download/image

echo "[+] Downloading kernel archive..."
wget ${RELEASE_URL}/${ARCHIVE}

echo "[+] Extracting..."
tar -xzf ${ARCHIVE}

echo "[+] Copying kernel files to /boot and /lib/modules..."
sudo cp chronos-kernel-backup-${VERSION}/vmlinuz-${VERSION} /boot/
sudo cp chronos-kernel-backup-${VERSION}/initrd.img-${VERSION} /boot/
sudo cp chronos-kernel-backup-${VERSION}/System.map-${VERSION} /boot/
sudo cp chronos-kernel-backup-${VERSION}/config-${VERSION} /boot/
sudo cp -r chronos-kernel-backup-${VERSION}/modules/${VERSION} /lib/modules/

echo "[+] Updating GRUB..."
sudo update-grub

echo "[+] Requesting safe reboot after profile setup..."
touch /local/.needreboot