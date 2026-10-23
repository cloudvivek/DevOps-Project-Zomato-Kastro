#!/bin/bash
set -e

# 1. Install Docker
sudo apt-get update -y
sudo apt-get install -y docker.io
sudo systemctl enable --now docker
sudo usermod -aG docker $USER

# 2. Install kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
rm kubectl

# 3. Install kind
curl -Lo ./kind https://kind.sigs.k8s.io/dl/latest/kind-linux-amd64
chmod +x ./kind
sudo mv ./kind /usr/local/bin/kind

# 4. Create kind cluster config (1 control-plane + 2 workers)
cat <<EOF > kind-config.yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
  - role: worker
  - role: worker
EOF

# 5. Create cluster (sudo needed until you re-login for docker group)
sudo kind create cluster --name my-cluster --config kind-config.yaml

# 6. Copy kubeconfig for current user
mkdir -p $HOME/.kube
sudo kind get kubeconfig --name my-cluster > $HOME/.kube/config
chmod 600 $HOME/.kube/config

# 7. Verify
kubectl get nodes
