#!/bin/bash
# Builds the kernel from source, installs it, and also builds the custom
# Chronos kernel module for the same version. Finally, creates two QEMU VMs
# and configures them for Chronos.

# Color (disable if not a TTY)
GREEN=$'\033[0;32m'
BLUE=$'\033[0;34m'
NC=$'\033[0m' # No Color
if ! test -t 1; then
    GREEN=""
    BLUE=""
    NC=""
fi


GITHUB_TOKEN="$1"
GITHUB_USERNAME="xyf2002"

if [ -z "$GITHUB_TOKEN" ]; then
    echo "Error: GitHub token not provided. Usage: ./build_kernel.sh <token>"
    exit 1
fi

kernel_repo="ujjwalpawar/chronos-kernel"
tsc_repo="ujjwalpawar/fake_tsc"
kernel_link="https://github.com/${kernel_repo}.git"
tsc_link="https://github.com/${tsc_repo}.git"
kernel_link="https://${GITHUB_USERNAME}:${GITHUB_TOKEN}@github.com/${kernel_repo}.git"
tsc_link="https://${GITHUB_USERNAME}:${GITHUB_TOKEN}@github.com/${tsc_repo}.git"
################################################################################
#
# Utility functions
#
################################################################################

function success() {
    printf "${GREEN}$1${NC}\n" "${@:2}"
}

function info() {
    printf "${BLUE}$1${NC}\n" "${@:2}"
}

################################################################################
#
# Command-line argument parsing
#
################################################################################
#info "Checking if kernel and tsc repos are public or need credentials"
## Check if either of the repos are not publicly accessible, and if so, ask for
## GitHub credentials to clone them. If the credentials are already provided in
## git-credentials, use them to clone the repos.
#if ! curl -s -L --head "${kernel_link}" | grep "HTTP/2 200" &> /dev/null ||
#   ! curl -s -L --head "${tsc_link}" | grep "HTTP/2 200" &> /dev/null;
#then
#    # Ask for GitHub credentials unless they already exist in ./git-credentials
#    if ! test -f git-credentials;
#    then
#        info "Will need to clone the following private repositories:"
#        info "  - ${kernel_link}"
#        info "  - ${tsc_link}"
#        echo "Please provide your GitHub username and a personal access token to continue."
#        echo -n "Username: "
#        read -r github_username
#        echo -n "Personal Access Token: "
#        read -r -s github_token
#        echo ""
#        info "Saving credentials to git-credentials"
#        echo "$github_username:$github_token" > git-credentials
#    else
#        info "Reading GitHub credentials from git-credentials"
#        github_username=$(cut -d: -f1 git-credentials)
#        github_token=$(cut -d: -f2 git-credentials)
#    fi
#
#    # Set the clone URLs to use the credentials instead of public link
#    kernel_link="https://${github_username}:${github_token}@github.com/${kernel_repo}.git"
#    tsc_link="https://${github_username}:${github_token}@github.com/${tsc_repo}.git"
#fi
#done

################################################################################
#
# Kernel Build
#
################################################################################


info "Installing kernel build dependencies"
sudo apt-get update
git clone ${kernel_link}
cd chronos-kernel
# Essentials for building the kernel
sudo apt-get install -y build-essential git libncurses-dev bison flex libssl-dev libelf-dev dwarves ripgrep

# Configure kernel based on current running config
info "Copying current kernel config to .config"
cp "/boot/config-$(uname -r)" .config # Copy the current kernel config

info "Disabling or enabling problematic kernel modules"
# Disable key-related options since they error out if not provided
scripts/config --disable SYSTEM_TRUSTED_KEYS
scripts/config --disable SYSTEM_REVOCATION_KEYS
# Disable this one particular camera driver since it errors
scripts/config --disable VIDEO_OV01A10
# Enable netfilter for VM networking with iptables
scripts/config --enable NETFILTER_XTABLES
scripts/config --enable NETFILTER_XT_MARK
scripts/config --enable NETFILTER_XT_TARGET_MARK
scripts/config --enable PREEMPT_RT_FULL
scripts/config --disable DEBUG_INFO_BTF
info "Running olddefconfig"
make olddefconfig
# Build the kernel
info "Building the kernel"
make "-j$(nproc)"
info "Installing the kernel"
sudo make INSTALL_MOD_STRIP=1 modules_install
sudo make install

# Set the default kernel to the new one for the next boot
sudo update-grub


################################################################################
#
# Extras
#
################################################################################

# Leave sources in place for inspection

echo "Kernel build complete"
sudo reboot

