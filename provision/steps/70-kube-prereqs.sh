#!/usr/bin/env bash
# Kubernetes worker prerequisites: containerd, kernel/sysctl, swap off, kube tools,
# max-pods drop-in. Stops short of 'kubeadm join' (needs a live cluster token).
set -euo pipefail
source "$HERE/config.env"
export DEBIAN_FRONTEND=noninteractive

if [[ "${SETUP_KUBE_PREREQS:-false}" != "true" ]]; then
  echo "SETUP_KUBE_PREREQS!=true — skipping."; exit 0
fi

# Swap off (kubelet requirement).
swapoff -a || true
sed -i.bak '/\sswap\s/s/^/#/' /etc/fstab || true

# Kernel modules + sysctl for the container network.
cat > /etc/modules-load.d/k8s.conf <<'EOF'
overlay
br_netfilter
EOF
modprobe overlay || true
modprobe br_netfilter || true
cat > /etc/sysctl.d/k8s.conf <<'EOF'
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system >/dev/null

# containerd with systemd cgroups.
apt-get install -y containerd
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
if [[ "${INSTALL_NVIDIA_CONTAINER_TOOLKIT:-false}" == "true" ]] && command -v nvidia-ctk >/dev/null; then
  nvidia-ctk runtime configure --runtime=containerd || true
fi
systemctl restart containerd
systemctl enable containerd

# kube tools from pkgs.k8s.io for the configured minor.
mkdir -p /etc/apt/keyrings
curl -fsSL "https://pkgs.k8s.io/core:/stable:/v${K8S_MINOR}/deb/Release.key" \
  | gpg --batch --yes --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${K8S_MINOR}/deb/ /" \
  > /etc/apt/sources.list.d/kubernetes.list
apt-get update -y
apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl

# max-pods (3 retiring workers total 143 pods > default 110; docs/05).
mkdir -p /etc/systemd/system/kubelet.service.d
cat > /etc/systemd/system/kubelet.service.d/20-max-pods.conf <<EOF
[Service]
Environment="KUBELET_EXTRA_ARGS=--max-pods=${KUBELET_MAX_PODS}"
EOF
systemctl daemon-reload

echo
echo "kube prereqs done (K8s v${K8S_MINOR}, max-pods=${KUBELET_MAX_PODS})."
echo "Finish on the control plane, then run the printed join, e.g.:"
echo "  sudo kubeadm join <API>:6443 --token <t> --discovery-token-ca-cert-hash sha256:<h>"
