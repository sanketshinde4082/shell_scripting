#!/bin/bash

set -e

MASTER_IP=<MASTER_PRIVATE_IP>   # <-- CHANGE THIS

echo "[1] Running kubeadm init..."
sudo kubeadm init \
  --pod-network-cidr=192.168.0.0/16 \
  --control-plane-endpoint=$MASTER_IP

echo "[2] Setting kubectl access..."
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

echo "[3] Installing Calico CNI..."
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.2/manifests/tigera-operator.yaml
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.2/manifests/custom-resources.yaml

echo "Waiting for Calico pods..."
watch kubectl get pods -n calico-system
