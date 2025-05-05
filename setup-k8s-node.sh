#!/bin/bash
# setup-k8s-node.sh

set -e

# 1. Obter papel do node via argumento
NODE_ROLE="$1"

if [[ -z "$NODE_ROLE" ]]; then
  echo "Uso: $0 <master|worker1|worker2>"
  exit 1
fi

# 2. Definir IP e hostname com base no papel
case "$NODE_ROLE" in
  master)
    IP="100.64.4.101"
    HOSTNAME="k8s-master"
    ;;
  worker1)
    IP="100.64.4.102"
    HOSTNAME="k8s-worker1"
    ;;
  worker2)
    IP="100.64.4.103"
    HOSTNAME="k8s-worker2"
    ;;
  *)
    echo "Papel inválido. Use: master, worker1 ou worker2"
    exit 1
    ;;
esac

echo "[1/9] Configurando hostname e IP fixo..."
sudo hostnamectl set-hostname "$HOSTNAME"

# 3. Configurar IP fixo via Netplan
sudo tee /etc/netplan/01-k8s.yaml > /dev/null <<EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    ens18:
      dhcp4: no
      addresses:
        - $IP/24
      gateway4: 100.64.4.1
      nameservers:
        addresses: [1.1.1.1, 8.8.8.8]
EOF

sudo netplan apply

# 4. Atualizar /etc/hosts
echo "[2/9] Atualizando /etc/hosts..."
sudo tee /etc/hosts > /dev/null <<EOF
127.0.0.1 localhost
$IP $HOSTNAME
100.64.4.101 k8s-master
100.64.4.102 k8s-worker1
100.64.4.103 k8s-worker2
EOF

# 5. Atualizar sistema
echo "[3/9] Atualizando sistema..."
sudo apt update && sudo apt upgrade -y
sudo apt install -y apt-transport-https ca-certificates curl gnupg software-properties-common

# 6. Desabilitar swap
echo "[4/9] Desabilitando swap..."
sudo swapoff -a
sudo sed -i '/ swap / s/^/#/' /etc/fstab

# 7. Configurar kernel
echo "[5/9] Configurando parâmetros de kernel..."
sudo modprobe overlay
sudo modprobe br_netfilter

cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sudo sysctl --system

# 8. Instalar Docker + Containerd
echo "[6/9] Instalando Docker e Containerd..."
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
sudo systemctl enable docker

sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml > /dev/null
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl restart containerd
sudo systemctl enable containerd

# 9. Instalar kubelet, kubeadm e kubectl
echo "[7/9] Instalando Kubernetes (kubelet, kubeadm, kubectl)..."
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | \
  sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /" | \
  sudo tee /etc/apt/sources.list.d/kubernetes.list > /dev/null

sudo apt update
sudo apt install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

# 10. Configurar SSH com chave
echo "[8/9] Configurando SSH para login com chave..."

SSH_KEY="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQC2znAE9d4j8BeouUde7ZL9rUyBwmYAbzMB/WDdekLV+d47imVxFuGsTc9y1BL7MoliO7RqOD6NccrgW6PLgEFItzdiNkBRlB4Feku+Ibo3V+v9QO2FaylkZcdPhF5zWVRFJAZVlRH61Sc15H5+V6g9Mt4srDmQOvrN9D9SULHdYnQg9png+IVyeZcyGDx6XqF+I7WTr2uztmtDyuoGnQD5BnJjvyjFuUZDc9Lf9HzGRO7qbHH4DguauVRnKF+NVuAsWQSAP2czY/db6BNaNGpBYOLNyTXAqjHKfhdWFHOXS3BRunds7XrkDSZCRKr+XF8CqlF8VQuIAIHYS0vwKCcGgRoHtbCvibrY0TL/4l5+yOA+u/39PKmO3co53dlPuiZThFJbnS7wrmiRDT878r/4uphBJ0r76n96yLDtQxuKq26LNo1QKFkMwCjewm8fTedEZWTH1Mxbi3WPxmkEBFVQBwi6comjXaSdOQC1EwX/RIGqUR7+ToQwK0rEwaNg54eFIhGdHmPFHAADdS5546lh1UPdfRrFAsH2Vdirz9aOcE9XwnxTC9SXtcJvkKV4IxleyMGAT3BZdT91Tp6++j/NDOpmq45jN2pN9QReJvmRDiZ4JKy5usR8W7IVcQVnUv2+i9201pnnMbaX4VOIzhlcpTe1w0jY23tTHw7FjaRXlQ== luis.sirqueira@laitude.sh"

mkdir -p ~/.ssh
echo "$SSH_KEY" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys

echo "[9/9] Fim da configuração do node: $HOSTNAME ($IP)"
