#================================
# Local variables
#================================

variable "libvirt_disk_path" {
  description = "path for libvirt pool"
  default     = "/tmp/terraform-provider-libvirt-pool-ubuntu"
}

variable "base_os_image_source" {
  description = "base os image source"
  default     = "./images/ubuntu-24.04-server-cloudimg-amd64.img"
  #  https://cloud-images.ubuntu.com/releases/24.04/release/ubuntu-24.04-server-cloudimg-amd64.img
}

variable "ssh_private_key" {
  description = "the private key to use"
  default     = "~/.ssh/id_ed25519"
}

#=====================================================================================
# Providers
#=====================================================================================
terraform {
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "0.7.1"
    }
  }
}

# Local provider for testing
provider "libvirt" {
  uri = "qemu:///system"
}

# # Remote provider with SSH authentication
# variable "ssh_host" {
#   description = "Remote host for SSH authentication"
#   type        = string
#   default     = "archlinux"
# }

# variable "ssh_username" {
#   description = "Username for SSH authentication" 
#   type        = string
#   default     = "admin"
# }

# variable "libvirt_password" {
#   description = "Password for SSH authentication"
#   type        = string
#   default     = ""
#   sensitive   = true
# }

# # Provider configuration for remote libvirt over SSH
# provider "libvirt" {
#   alias = "remote"
#   # Password-based authentication
#   uri = "qemu+ssh://${var.ssh_username}:${var.libvirt_password}@${var.ssh_host}/system"
# }

# # Usage Instructions For password authentication:
# #   export LIBVIRT_PASSWORD=your_password_here
# #   terraform apply -var "libvirt_password=${LIBVIRT_PASSWORD}" \
# #                  -var "ssh_username=your_username" \
# #                  -var "ssh_host=your_host"


# # Alternative provider configuration using SSH key authentication
# provider "libvirt" {
#   alias = "remote_key"
#   # Key-based authentication using existing ssh_private_key variable
#   uri = "qemu+ssh://${var.ssh_username}@${var.ssh_host}/system?keyfile=${var.ssh_private_key}"
# }

# # Usage Instructions For SSH key authentication:
# #   terraform apply -var "ssh_username=your_username" \
# #                  -var "ssh_host=your_host" \
# #                  -var "ssh_private_key=/path/to/private/key" \
# #                  -provider=libvirt.remote_key


#=====================================================================================
# Libvirt Pool
#=====================================================================================
resource "libvirt_pool" "kubernetes" {
  name = "kubernetes"
  type = "dir"
  # target {
  path = var.libvirt_disk_path
  # }
}
#=====================================================================================
# Cloudinit
#=====================================================================================
data "template_file" "user_data" {
  template = file("${path.module}/cloud_init/cloud_init.yaml")
}

data "template_file" "network_config" {
  template = file("${path.module}/cloud_init/network_config.yaml")
}

# paru -S cdrtools or apt install genisoimage
resource "libvirt_cloudinit_disk" "cloudinit" {
  name           = "cloudinit.iso"
  pool           = libvirt_pool.kubernetes.name
  user_data      = data.template_file.user_data.rendered
  network_config = data.template_file.network_config.rendered
}

#=====================================================================================
# Disk
#=====================================================================================
resource "libvirt_volume" "base_os" {
  name   = "base_os"
  pool   = libvirt_pool.kubernetes.name
  source = var.base_os_image_source
  format = "qcow2"
}

resource "libvirt_volume" "disk_resized" {
  name           = "root_disk"
  pool           = libvirt_pool.kubernetes.name
  base_volume_id = libvirt_volume.base_os.id
  format         = "qcow2"
  size           = 20 * 1024 * 1024 * 1024 # 20GiB
}

resource "libvirt_volume" "disk_data" {
  name   = "data_disk"
  pool   = libvirt_pool.kubernetes.name
  format = "qcow2"
  size   = 10 * 1024 * 1024 * 1024 # 10GiB
}

#=====================================================================================
# Network
#=====================================================================================
resource "libvirt_network" "kubernetes" {
  name      = "kubernetes"
  mode      = "bridge"
  bridge    = "br0" # Use the created bridge network card
  autostart = true
}
#=====================================================================================
# Domain
#=====================================================================================
resource "libvirt_domain" "domain-ubuntu" {
  name   = "ubuntu"
  memory = "512"
  vcpu   = 1
  cloudinit  = libvirt_cloudinit_disk.cloudinit.id
  qemu_agent = true

  network_interface {
    network_id     = libvirt_network.kubernetes.id
    wait_for_lease = true
  }


  # 主系统盘
  disk {
    volume_id = libvirt_volume.disk_resized.id
  }

  # 数据盘
  disk {
    volume_id = libvirt_volume.disk_data.id
  }
  #=====================================================================================
  # Console
  #=====================================================================================
  console {
    type        = "pty"
    target_port = "0"
    target_type = "serial"
  }

  console {
    type        = "pty"
    target_type = "virtio"
    target_port = "1"
  }

  graphics {
    type        = "spice"
    listen_type = "address"
    autoport    = true
  }




  # provisioner "remote-exec" {
  #   inline = [
  #     <<-EOF
  #     set -x
  #     id
  #     #uname -a
  #     #cat /etc/os-release
  #     #echo "machine-id is $(cat /etc/machine-id)"
  #     ## rm -f  /etc/machine-id    #删掉原有的machine-id的文件
  #     ## rm -f /var/lib/dbus/machine-id 
  #     ## systemd-machine-id-setup    #执行重新生成命令      
  #     ## systemd-networkd 默认使用 /etc/machine-id 来识别，当虚拟机克隆的时候，他们都有一样的 /etc/machine-id 和 DHCP server, 会导致返回的都是同一个 ip 。
  #     #hostname --fqdn
  #     #cat /etc/hosts
  #     #sudo sfdisk -l
  #     #lsblk -x KNAME -o KNAME,SIZE,TRAN,SUBSYSTEMS,FSTYPE,UUID,LABEL,MODEL,SERIAL
  #     #mount | grep -E "^/dev"
  #     #df -Th
  #     EOF
  #   ]
  # }
  # connection {
  #   type = "ssh"
  #   user = "ubuntu"
  #   host = self.network_interface[0].addresses[0]
  #   # host        = libvirt_domain.domain-debian9-qcow2.network_interface[0].addresses[0]
  #   private_key = file("~/.ssh/id_ed25519")
  #   #   bastion_host        = "archlinux"
  #   #   bastion_user        = "admin"
  #   #   bastion_private_key = file("~/.ssh/id_ed25519")
  #   timeout = "2m"
  # }
  # # lifecycle {
  # #   ignore_changes = [
  # #     nvram,
  # #     disk[0].wwn,
  # #     network_interface[0].addresses,
  # #   ]
  # # }  
  # # provisioner "local-exec" {
  # #   command = <<EOT
  # #     echo "[nginx]" > ansible/nginx.ini
  # #     echo "${libvirt_domain.domain-ubuntu.network_interface[0].addresses[0]}" ansible_user=ubuntu>> ansible/nginx.ini
  # #     echo "[nginx:vars]" >> ansible/nginx.ini
  # #     echo "ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'" >> ansible/nginx.ini
  # #     # echo "ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ProxyCommand=\"ssh -W %h:%p -q archlinux\"'" >> ansible/nginx.ini
  # #     ansible-playbook -u ${var.ssh_username} --private-key ${var.ssh_private_key} -i ansible/nginx.ini ansible/playbook.yml
  # #     EOT
  # # }    

}

# Output the IP addresses
output "ips" {
  value = {
    ip = libvirt_domain.domain-ubuntu.network_interface[0].addresses
  }
}
