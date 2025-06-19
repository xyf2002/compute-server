#K8S_VERSION="1.26.1-00"
K8S_VERSION="1.24.14-1.1"
WORKINGDIR='/local/repository'
username=$(id -un)
HOME=/users/$(id -un)
usergid=$(id -ng)
KUBEHOME="${WORKINGDIR}/kube"



# Create extra storage for K8s and containerd
# Define storage folder (this should match with the path specified in setup-disk.sh)
STORAGEDIR=/storage
sudo mkdir -p $STORAGEDIR/kubelet $STORAGEDIR/containerd
# kubelet
sudo ln -s $STORAGEDIR/kubelet/ /var/lib/kubelet
# containerd
sudo ln -s $STORAGEDIR/containerd/ /var/lib/containerd


# Change login shell for user
sudo chsh -s /bin/bash $username

sudo chown ${username}:${usergid} ${WORKINGDIR}/ -R
cd $WORKINGDIR

mkdir -p $KUBEHOME
export KUBECONFIG=$KUBEHOME/admin.conf
echo "export KUBECONFIG=${KUBECONFIG}" > $HOME/.profile

# Add repositories
# Kubernetes
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add
sudo apt-add-repository "deb http://apt.kubernetes.io/ kubernetes-xenial main"

# Update apt lists
sudo apt-get update

# Install pre-reqs
sudo apt-get -y install apt-transport-https xgrep jq

# Patch Kubernetes issue by adding new apt source
sudo apt-get install -y apt-transport-https ca-certificates curl
sudo mkdir -m 755 /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.24/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.24/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list

# Disable swapoff
sudo swapoff -a
# Disable swap permanently
sudo sed -e '/swap/ s/^#*/#/' -i /etc/fstab

##############
# Containerd #
##############
# Configure required modules
sudo modprobe overlay
sudo modprobe br_netfilter
cat <<EOF | sudo tee /etc/modules-load.d/containerd.conf
overlay
br_netfilter
EOF
# Configure required sysctl to persist across system reboots
cat <<EOF | sudo tee /etc/sysctl.d/99-kubernetes-cri.conf
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF
# Apply sysctl parameters without reboot to current running enviroment
sudo sysctl --system
# Install containerd
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
sudo apt update -y
sudo apt install -y containerd.io
# Create configuration file
sudo mkdir -p /etc/containerd
sudo containerd config default | sudo tee /etc/containerd/config.toml
# Set containerd cgroup driver to systemd
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
# Restart containerd daemon
sudo systemctl daemon-reload
sudo systemctl restart containerd
sudo systemctl enable containerd
sudo apt-mark hold containerd

##############
# Kubernetes #
##############
sudo apt-get -y install kubelet=$K8S_VERSION kubeadm=$K8S_VERSION kubectl=$K8S_VERSION
# Prevent packages from being modified
sudo apt-mark hold kubelet kubeadm kubectl

sudo systemctl enable kubelet.service

echo "Kubernetes and Containerd installed"
