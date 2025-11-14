#!/bin/bash
set -euo pipefail
# master.sh - prepare & initialize master (kubeadm). Idempotent.
 
if [[ $EUID -ne 0 ]]; then
  echo "Run as root or with sudo: sudo ./master.sh"
  exit 1
fi
 
POD_CIDR=${POD_CIDR:-"192.168.0.0/16"}
K8S_REPO_KEY="/etc/apt/keyrings/kubernetes-apt-keyring.gpg"
CALICO_MANIFEST="https://docs.projectcalico.org/manifests/calico.yaml"
JOIN_OUTPUT="/tmp/kubeadm_join_cmd.sh"
 
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
#!/bin/bash
 
initialize_master() {
  # If admin.conf exists, assume cluster already initialized
  if [[ -f /etc/kubernetes/admin.conf ]]; then
    echo "Kubernetes control plane already initialized on this host."
    echo "Skipping kubeadm init."
  else
    kubeadm init --pod-network-cidr="$POD_CIDR"
  fi
 
  # copy kubeconfig for current user (root or sudo caller)
  TARGET_HOME=${SUDO_USER:+/home/$SUDO_USER:$SUDO_USER}
  # if script run as sudo, set up for the invoking user; otherwise root.
  if [[ -n "${SUDO_USER:-}" ]]; then
    mkdir -p /home/"${SUDO_USER}"/.kube
    cp -i /etc/kubernetes/admin.conf /home/"${SUDO_USER}"/.kube/config
    chown "${SUDO_UID:-0}":"${SUDO_GID:-0}" /home/"${SUDO_USER}"/.kube/config
    echo "kubectl config copied to /home/${SUDO_USER}/.kube/config"
  else
    mkdir -p $HOME/.kube
    cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
    chown $(id -u):$(id -g) $HOME/.kube/config
    echo "kubectl config copied to $HOME/.kube/config"
  fi
 
  # ensure kubectl in PATH for immediate usage
  export KUBECONFIG=/etc/kubernetes/admin.conf
}
 
apply_cni_and_output_join() {
  kubectl apply -f "$CALICO_MANIFEST"
 
  # Create (or refresh) a reusable join command (auto-creates token if needed)
  echo "#!/bin/bash" > "$JOIN_OUTPUT"
  kubeadm token create --print-join-command >> "$JOIN_OUTPUT"
  chmod +x "$JOIN_OUTPUT"
  echo "Join command saved to: $JOIN_OUTPUT"
  echo "Print the join command:"
  cat "$JOIN_OUTPUT"
}
 
main() {
  install_base
  disable_swap
  enable_kernel_modules
  install_containerd
  install_k8s_tools
  initialize_master
  apply_cni_and_output_join
  echo "Master setup complete. Run 'kubectl get nodes' after a minute to see node status."
}
 
main "$@"
