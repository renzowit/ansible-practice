terraform {
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "0.7.6"
    }
  }
}

provider "libvirt" {
  uri = "qemu:///system"
}

resource "libvirt_volume" "os_image" {
  name   = "ubuntu-base.qcow2"
  pool   = "default"
  source = "https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
  format = "qcow2"
}

resource "libvirt_volume" "vm_disk" {
  count          = 1
  name           = "vm-disk-${count.index}.qcow2"
  base_volume_id = libvirt_volume.os_image.id
  pool           = "default"
  size           = 10737418240
}

resource "libvirt_cloudinit_disk" "commoninit" {
  count     = 1
  name      = "commoninit-${count.index}.iso"
  user_data = templatefile("${path.module}/cloud_init.cfg", {
    ssh_key = file("~/.ssh/id_rsa.pub")
  })
  pool      = "default"
}

resource "libvirt_domain" "ubuntu_vm" {
  count  = 1
  name   = "ansible-vm-${count.index}"
  memory = "2048"
  vcpu   = 1

  cloudinit = libvirt_cloudinit_disk.commoninit[count.index].id

  network_interface {
    network_name   = "default"
    wait_for_lease = true
  }

  disk {
    volume_id = libvirt_volume.vm_disk[count.index].id
  }

  console {
    type        = "pty"
    target_port = "0"
    target_type = "serial"
  }
}

output "ips" {
  value = libvirt_domain.ubuntu_vm.*.network_interface.0.addresses
}

resource "local_file" "ansible_inventory" {
  content = templatefile("inventory.tmpl", {
    ip_addrs = [for vm in libvirt_domain.ubuntu_vm : vm.network_interface[0].addresses[0]]
  })
  filename = "inventory.ini"
}