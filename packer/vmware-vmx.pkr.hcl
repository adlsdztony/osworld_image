source "vmware-vmx" "osworld" {
  source_path      = var.vmware_source_vmx
  output_directory = var.vmware_output_directory
  vm_name          = var.vmware_vm_name

  headless         = var.headless
  shutdown_command = "echo '${var.ssh_password}' | sudo -S shutdown -P now"
  ssh_password     = var.ssh_password
  ssh_timeout      = var.ssh_timeout
  ssh_username     = var.ssh_username

  vmx_data = {
    memsize  = "8192"
    numvcpus = "4"
  }
}

build {
  name    = "vmware"
  sources = ["source.vmware-vmx.osworld"]

  provisioner "ansible" {
    playbook_file   = "${path.root}/../ansible/playbook.yml"
    use_proxy       = true
    ansible_env_vars = [
      "ANSIBLE_BECOME_PASSWORD_FILE=${path.root}/../scripts/ansible-become-pass.sh",
      "OSWORLD_SUDO_PASSWORD=${var.ssh_password}",
    ]
    extra_arguments = concat(local.ansible_common_args, ["--extra-vars", "target_platform=vmware"])
  }
}
