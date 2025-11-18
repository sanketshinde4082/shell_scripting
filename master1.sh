#!/bin/bash

set -e

MASTER_IP=<MASTER_PRIVATE_IP>   # <-- CHANGE THIS

echo "[1] Running kubeadm init..."

sudo kubeadm init --pod-network-cidr=192.168.0.0/16
kubeadm join <MASTER-IP>:6443 --token <TOKEN> \
    --discovery-token-ca-cert-hash sha256:<HASH>

echo "[2] Setting kubectl access..."

mkdir -p $HOME/.kube
sudo cp /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

echo "[3] Installing Calico CNI..."
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.2/manifests/calico.yaml

echo "Waiting for Calico pods..."
watch kubectl get pods -n calico-system
