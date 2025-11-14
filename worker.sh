#!/bin/bash
set -euo pipefail
# worker.sh - prepare worker node and run kubeadm join
# Usage:
#   sudo ./worker.sh "kubeadm join ... --token ... --discovery-token-ca-cert-hash ..."
 
if [[ $EUID -ne 0 ]]; then
  echo "Run as root or with sudo: sudo ./worker.sh \"<join-command>\""
  exit 1
fi
 
JOIN_CMD="${1:-}"
JOIN_FILE="/tmp/kubeadm_join_cmd.sh"
 
POD_CIDR=${POD_CIDR:-"192.168.0.0/16"}
K8S_REPO_KEY="/etc/apt/keyrings/kubernetes-apt-keyring.gpg"
 
install_base() {
  apt-get update
  apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release socat conntrack ipset
}
 
disable_swap() {
  swapoff -a
  sed -i.bak '/ swap / s/^/#/' /etc/fstab || true
}
 
enable_kernel_modules() {
  cat > /etc/modules-load.d/k8s.conf <<EOF
overlay
br_netfilter
EOF
  modprobe overlay || true
  modprobe br_netfilter || true
  cat > /etc/sysctl.d/k8s.conf <<EOF
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF
  sysctl --system
}
 
install_containerd() {
  apt-get update
  apt-get install -y containerd
  mkdir -p /etc/containerd
  containerd config default | tee /etc/containerd/config.toml >/dev/null
  sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml || true
  systemctl restart containerd
  systemctl enable containerd
}
 
install_k8s_tools() {
  apt-get update
  apt-get install -y apt-transport-https ca-certificates curl gpg
  mkdir -p /etc/apt/keyrings
  curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | gpg --dearmor -o "$K8S_REPO_KEY"
  echo "deb [signed-by=$K8S_REPO_KEY] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /" > /etc/apt/sources.list.d/kubernetes.list
  apt-get update
  apt-get install -y kubelet kubeadm kubectl
  apt-mark hold kubelet kubeadm kubectl
}
 
join_cluster() {
  if [[ -z "$JOIN_CMD" ]]; then
    if [[ -f "$JOIN_FILE" ]]; then
      JOIN_CMD=$(cat "$JOIN_FILE" | sed -n '2p' || true)  # second line has join command
    fi
  fi
 
  if [[ -z "$JOIN_CMD" ]]; then
    echo "No join command provided. Usage:"
    echo "  sudo ./worker.sh \"kubeadm join <master-ip>:6443 --token ... --discovery-token-ca-cert-hash ...\""
    echo "Or copy /tmp/kubeadm_join_cmd.sh from master to this node and run without args."
    exit 1
  fi
 
  # run join; require running as root (this script already ensures root)
  eval "$JOIN_CMD"
}
 
main() {
  install_base
  disable_swap
  enable_kernel_modules
  install_containerd
  install_k8s_tools
  join_cluster
  echo "Worker join attempted. On master run 'kubectl get nodes' to verify."
}
 
main "$@"
