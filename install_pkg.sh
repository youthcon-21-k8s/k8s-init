#!/usr/bin/env bash

# install packages 
yum install epel-release vim-enhanced git lvm2 wget iscsi-initiator-utils -y

# install kubernetes cluster 
yum install containerd.io kubectl-$1 kubelet-$1 kubeadm-$1 -y
sudo mkdir -p /etc/containerd
systemctl enable --now kubelet
systemctl enable --now containerd
containerd config default | sudo tee /etc/containerd/config.toml
systemctl restart containerd
systemctl enable --now iscsid



# git clone _Book_k8sInfra.git 
if [ $2 = 'Main' ]; then
  git clone https://github.com/sysnet4admin/_Book_k8sInfra.git
  mv /home/vagrant/_Book_k8sInfra $HOME
  find $HOME/_Book_k8sInfra/ -regex ".*\.\(sh\)" -exec chmod 700 {} \;
fi
