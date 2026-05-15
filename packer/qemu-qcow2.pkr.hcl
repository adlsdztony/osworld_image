source "qemu" "osworld" {
  accelerator      = var.qemu_accelerator
  cpus             = 4
  memory           = 8192
  disk_image       = true
  disk_interface   = "virtio"
  format           = "qcow2"
  headless         = var.headless
  iso_checksum     = var.qemu_source_qcow2_checksum
  iso_url          = var.qemu_source_qcow2
  net_device       = "virtio-net"
  output_directory = "${var.qemu_output_directory}-${local.effective_build_id}"
  shutdown_command = "echo 'osworld-public-evaluation' | sudo -S shutdown -P now"
  skip_resize_disk = true
  ssh_password     = var.ssh_password
  ssh_timeout      = var.ssh_timeout
  ssh_username     = var.ssh_username
  use_backing_file = false
  vm_name          = var.qemu_vm_name

  qemuargs = [
    ["-display", "none"],
    ["-device", "virtio-vga"],
    ["-cpu", "host"],
  ]
}

build {
  name    = "qemu"
  sources = ["source.qemu.osworld"]

  provisioner "ansible" {
    playbook_file   = "${path.root}/../ansible/playbook.yml"
    use_proxy       = true
    ansible_env_vars = [
      "ANSIBLE_CONFIG=${path.root}/../ansible.cfg",
      "ANSIBLE_REMOTE_TEMP=/tmp/.ansible-osworld",
      "ANSIBLE_REMOTE_TMP=/tmp/.ansible-osworld",
      "ANSIBLE_BECOME_PASSWORD_FILE=${path.root}/../scripts/ansible-become-pass.sh",
      "OSWORLD_SUDO_PASSWORD=${var.ssh_password}",
    ]
    extra_arguments = concat(local.ansible_common_args, ["--extra-vars", "target_platform=qemu"])
  }
}
