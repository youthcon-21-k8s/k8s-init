# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure("2") do |config|
  N = 1 # max number of worker nodes
  Ver = '1.22.3' # Kubernetes Version to install
  
  #=============#
  # Master Node #
  #=============#

    config.vm.define "m-k8s-y" do |cfg|
      cfg.vm.box = "sysnet4admin/CentOS-k8s"
      cfg.vm.provider "virtualbox" do |vb|
        vb.name = "m-k8s(youthcon)"
        vb.cpus = 2
        vb.memory = 3072
        vb.customize ["modifyvm", :id, "--groups", "/k8s-youthcon"]
      end
      cfg.vm.host_name = "m-k8s-y"
      cfg.vm.network "private_network", ip: "192.168.1.10"
      cfg.vm.network "forwarded_port", guest: 22, host: 60010, auto_correct: true, id: "ssh"
      cfg.vm.synced_folder "../data", "/vagrant", disabled: true 
      cfg.vm.provision "shell", path: "config.sh", args: N
      cfg.vm.provision "shell", path: "install_pkg.sh", args: [ Ver, "Main" ]
      cfg.vm.provision "shell", path: "master_node.sh"
    end

  #==============#
  # Worker Nodes #
  #==============#

  (1..N).each do |i|
    config.vm.define "w#{i}-k8s-y" do |cfg|
      cfg.vm.box = "sysnet4admin/CentOS-k8s"
      cfg.vm.provider "virtualbox" do |vb|
        vb.name = "w#{i}-k8s(youthcon)"
        vb.cpus = 1
        vb.memory = 2048
        vb.customize ["modifyvm", :id, "--groups", "/k8s-youthcon"]
      end
      cfg.vm.host_name = "w#{i}-k8s-y"
      cfg.vm.network "private_network", ip: "192.168.1.10#{i}"
      cfg.vm.network "forwarded_port", guest: 22, host: "6010#{i}", auto_correct: true, id: "ssh"
      cfg.vm.synced_folder "../data", "/vagrant", disabled: true
      cfg.vm.provision "shell", path: "config.sh", args: N
      cfg.vm.provision "shell", path: "install_pkg.sh", args: Ver
      cfg.vm.provision "shell", path: "work_nodes.sh"
    end
  end
  
  # for ceph
  (1..N).each do |i|
    config.vm.define "s#{i}-k8s-y" do |cfg|
      cfg.vm.box = "sysnet4admin/CentOS-k8s"
      cfg.vm.provider "virtualbox" do |vb|
        vb.name = "s#{i}-k8s(youthcon)"
        vb.cpus = 1
        vb.memory = 2048
        vb.customize ["modifyvm", :id, "--groups", "/k8s-youthcon"]
        file_check = "disk#{i}.vmdk"
        unless File.exist?(file_check)
          vb.customize [ "createmedium", "disk", "--filename", "disk#{i}.vmdk", "--format", "vmdk", "--size", 1024 * 10 ]
        end
        vb.customize [ "storageattach", :id, "--storagectl", "SATA", "--port", "1", "--device", "0", "--type", "hdd", "--medium", "disk#{i}.vmdk"]
      end
      cfg.vm.host_name = "s#{i}-k8s-y"
      cfg.vm.network "private_network", ip: "192.168.1.11#{i}"
      cfg.vm.network "forwarded_port", guest: 22, host: "6020#{i}", auto_correct: true, id: "ssh"
      cfg.vm.synced_folder "../data", "/vagrant", disabled: true
      cfg.vm.provision "shell", path: "config.sh", args: N
      cfg.vm.provision "shell", path: "install_pkg.sh", args: Ver
      cfg.vm.provision "shell", path: "work_nodes.sh"
    end
  end
end