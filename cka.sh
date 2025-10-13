#!/bin/bash
#################### CKA Setup ####################
# Copyright: MYRC Enterprise, 2025
#
# VM Spec:
# 	VCPU: 2
# 	Memory: 4Gb
# 	OS: Ubuntu 24.04 LTS
#
# Usage:
# 	cka.sh master|worker
#
# Assumptions:
# 	- only 1 network interface, if >1 then modify Step 1 hostname -I
#
# Limitations:
# 	- only works for 1 master & 1 worker
###################################################
# Record start time
start_time=$SECONDS

# Environment Variables
export LOCAL_USER=student
export LOG_FILE=/home/$LOCAL_USER/script.log
export K8S_VERSION=1.33.1
export K8S_GPG_VER=v1.33
export POD_NTWK=10.0.0.0/16
if [ -z "$1" ]; then
	echo Usage: $0 HOSTNAME >&2
	echo -e "\t Where HOSTNAME=master|worker" >&2
	exit 1
elif [ $1 == 'master' -o $1 == 'worker' ]; then
	export K8S_HOST=$1
else
	echo Invalid HOSTNAME >&2
	exit 1
fi
export MANUAL_SETUP=false

# function declaration
show_ok() {
	local green='\033[0;32m'
	local reset='\033[0m'
	echo -e "${green}ok${reset}\n" | tee -a $LOG_FILE
}

show_fail() {
	local red='\033[0;31m'
	local reset='\033[0m'
	echo -e "${red}fail${reset}\n" | tee -a $LOG_FILE
	exit 1
}

show_title() {
    local text="$*"
    local total_length=50
    local ok_length=2  # "ok" is 2 characters
    
    # Calculate available space for text and dots
    local available_space=$((total_length - ok_length))
    local text_length=${#text}
    
    if [ $text_length -ge $available_space ]; then
        # If text is too long, truncate it
	echo -n "${text:0:$((available_space-1))}."
    else
        # Calculate how many dots we need
        local dots_needed=$((available_space - text_length))
        local dots=$(printf '%*s' $dots_needed | tr ' ' '.')
	echo -n "${text}${dots}"
    fi | tee -a $LOG_FILE
}

finish() {
	duration=$(( SECONDS - start_time ))
	echo -e "\n\n\nScript executed in $((duration%3600/60)) minutes and $((duration%60)) seconds.\n"
}

trap finish EXIT

show_title "Step 0: Check process owner"
if [ `id --user` -ne 0 ]; then
	echo -e '\nSwitch user to root using "sudo -i" before executing this script.' >&2
	exit 1
else
	show_ok
fi

show_title "Step 1: Set hostname"
hostnamectl hostname $K8S_HOST
hostname -i | grep '^127' -q && LOCAL_IP=`hostname -I|awk '{print $1}'` || LOCAL_IP=`hostname -i`
grep -q "$LOCAL_IP\s*$K8S_HOST" /etc/hosts || sed -i "1i\\$LOCAL_IP $K8S_HOST" /etc/hosts
echo -e "\n\n"
head -1 /etc/hosts
read -p "type any character and press enter to stop if hosts is wrong" -t 5 DO_STOP
if [ -n "$DO_STOP" ]; then
	echo Get your instructor to help >&2
       	exit 1
else
	show_ok
fi

show_title "Step 2: Update & Upgrade packages"
(apt update && apt upgrade -y) &>> $LOG_FILE && show_ok || show_fail

show_title "Step 3: Install prerequisite packages"
(apt install -y apt-transport-https software-properties-common ca-certificates socat vim curl gnupg2 lsb-release wget bash-completion tree &>> $LOG_FILE) && show_ok || show_fail

show_title "Step 4: Disable swap"
(swapoff -a
sed -i '/^[^#].*\s*swap\s*.*/s/^/#/' /etc/fstab) &>> $LOG_FILE && show_ok || show_fail

show_title "Step 5: Auto load modules"
(cat << EOF | tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter) &>> $LOG_FILE && show_ok || show_fail

show_title "Step 6: Configure kernel parameters"
(cat << EOF | tee /etc/sysctl.d/kubernetes.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF

sysctl --system) &>> $LOG_FILE && show_ok || show_fail

show_title "Step 7: Add kubernetes and containerd gpg keys"
(curl -fsSL https://pkgs.k8s.io/core:/stable:/$K8S_GPG_VER/deb/Release.key \
	| sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg && \ 
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
	| sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg) &>> $LOG_FILE && show_ok || show_fail 

show_title "Step 7: Add kubernetes and containerd repos"
(echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] \
	https://pkgs.k8s.io/core:/stable:/$K8S_GPG_VER/deb/ /" \
	| sudo tee /etc/apt/sources.list.d/kubernetes.list

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
	https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
	| sudo tee /etc/apt/sources.list.d/docker.list) &>> $LOG_FILE && show_ok || show_fail

show_title "Step 8: Install and configure containerd"
##### pause:3.10 ADDED BY KELVIN
(apt update && apt install containerd.io -y && \
containerd config default | tee /etc/containerd/config.toml && \
sed -e 's/SystemdCgroup = false/SystemdCgroup = true/g' -i /etc/containerd/config.toml && \
sed -e 's/pause:3.8/pause:3.10/' -i /etc/containerd/config.toml && \
systemctl restart containerd && \
systemctl enable containerd) &>> $LOG_FILE && show_ok || show_fail

show_title "Step 9: Install kubeadm kubectl and kubelet"
$MANUAL_SETUP && exit 0
(apt update && \
apt install -y kubeadm=${K8S_VERSION}-* kubectl=${K8S_VERSION}-* kubelet=${K8S_VERSION}-* && \
apt-mark hold kubeadm kubectl kubelet) &>> $LOG_FILE && show_ok || show_fail

show_title "Step 9: Fix containerd runtime endpoint"
# DO THIS IN WORKER AS WELL - BY KELVIN
crictl config \
	--set runtime-endpoint=unix:///run/containerd/containerd.sock \
	--set image-endpoint=unix:///run/containerd/containerd.sock  &>> $LOG_FILE && show_ok || show_fail

show_title "Step 10: Install kubernetes"
# To generate a default config:
# 	kubeadm config print init-defaults > kubeadm-config.yaml
if [ $K8S_HOST == 'master' ]; then
	echo | tee -a  script.log
	kubeadm init \
		--kubernetes-version=$K8S_VERSION \
		--pod-network-cidr=$POD_NTWK \
		--upload-certs \
		--node-name=$K8S_HOST \
		--control-plane-endpoint=$K8S_HOST:6443 \
		| tee -a kubeadm-init.log script.log
	if [ $? -ne 0 ]; then
		echo FAILED KUBEADM
		show_fail
	else
		show_ok
	fi

	show_title "Step 11: Configure kubectl for $LOCAL_USER"
	(mkdir -p /home/$LOCAL_USER/.kube
	cp /etc/kubernetes/admin.conf /home/$LOCAL_USER/.kube/config
	chown -R $LOCAL_USER:$LOCAL_USER /home/$LOCAL_USER/.kube
	
	mkdir -p /etc/bash_completion.d
	kubectl completion bash > /etc/bash_completion.d/kubectl
	) &>> $LOG_FILE && show_ok || show_fail
else
	echo -e Skip | tee -a script.log
fi

if [ $K8S_HOST == 'master' ]; then
	show_title "Step 12: Configure CNI - Cilium"
	(snap install helm --classic
	helm repo add cilium https://helm.cilium.io/
	helm repo update
	helm template cilium cilium/cilium --version 1.16.1 --namespace kube-system > cilium.yaml
	KUBECONFIG=/etc/kubernetes/admin.conf kubectl apply -f cilium.yaml) &>> $LOG_FILE && show_ok || show_fail
else
	echo -e "\n\n\n\n\n1. Add this line to /etc/hosts in master node"
	head -1 /etc/hosts
	echo -e "\n\n\n\n\n2. Add master node info into /etc/hosts in this worker node"

	echo -e "\n\n3. run this command in master node"
	echo -e "\tkubeadm token create --print-join-command"
	echo -e "\n4. Copy the result and execute it in this worker node"
fi

echo Completed | tee -a $LOG_FILE
date
