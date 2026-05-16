source "qemu" "windows_osworld" {
  accelerator       = var.qemu_accelerator
  communicator      = "winrm"
  cpus              = 4
  memory            = 4096
  boot_wait         = "90s"
  boot_key_interval = "15ms"
  boot_command = [
    "<leftCtrlOn><esc><leftCtrlOff><wait1s>",
    "powershell<wait1s>",
    "<leftCtrlOn><leftShiftOn><enter><leftShiftOff><leftCtrlOff><wait5s>",
    "<leftAltOn>y<leftAltOff><wait5s>",
    "winrm quickconfig -q<enter><wait2s>",
    "netsh advfirewall firewall set rule group=\"windows remote management\" new enable=yes<enter><wait2s>",
    "reg add hklm\\software\\microsoft\\windows\\currentversion\\policies\\system /v localaccounttokenfilterpolicy /t reg_dword /d 1 /f<enter><wait2s>",
    "winrm set winrm/config/service/auth '@{Basic=\"true\"}'<enter><wait2s>",
    "winrm set winrm/config/service '@{AllowUnencrypted=\"true\"}'<enter><wait2s>",
    "net user ${var.windows_winrm_username} /active:yes<enter><wait2s>",
    "net user ${var.windows_winrm_username} ${var.windows_winrm_password}<enter><wait2s>",
    "$user='${var.windows_winrm_username}'; $password='${var.windows_winrm_password}'; $winlogon='HKLM:\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Winlogon'<enter><wait1s>",
    "$sid=(Get-LocalUser -Name $user).SID.Value<enter><wait1s>",
    "New-ItemProperty -Path $winlogon -Name AutoAdminLogon -PropertyType String -Value '1' -Force | Out-Null<enter><wait1s>",
    "New-ItemProperty -Path $winlogon -Name ForceAutoLogon -PropertyType String -Value '1' -Force | Out-Null<enter><wait1s>",
    "New-ItemProperty -Path $winlogon -Name DefaultUserName -PropertyType String -Value $user -Force | Out-Null<enter><wait1s>",
    "New-ItemProperty -Path $winlogon -Name DefaultPassword -PropertyType String -Value $password -Force | Out-Null<enter><wait1s>",
    "New-ItemProperty -Path $winlogon -Name DefaultDomainName -PropertyType String -Value $env:COMPUTERNAME -Force | Out-Null<enter><wait1s>",
    "New-ItemProperty -Path $winlogon -Name AutoLogonSID -PropertyType String -Value $sid -Force | Out-Null<enter><wait1s>",
    "Restart-Computer -Force<enter><wait5s>",
  ]
  disk_image       = true
  disk_interface   = "ide"
  firmware         = var.windows_efi_firmware
  format           = "qcow2"
  headless         = var.headless
  iso_checksum     = var.windows_source_qcow2_checksum
  iso_url          = var.windows_source_qcow2
  net_device       = "e1000"
  output_directory = "${var.windows_output_directory}-${local.effective_build_id}"
  shutdown_command = "shutdown /s /t 10 /f /d p:4:1 /c \"Packer shutdown\""
  skip_resize_disk = true
  use_backing_file = false
  vm_name          = var.windows_vm_name

  winrm_insecure = true
  winrm_password = var.windows_winrm_password
  winrm_timeout  = var.windows_winrm_timeout
  winrm_use_ssl  = false
  winrm_use_ntlm = true
  winrm_username = var.windows_winrm_username

  qemuargs = [
    ["-display", "none"],
    ["-cpu", "host"],
  ]
}

build {
  name    = "windows"
  sources = ["source.qemu.windows_osworld"]

  provisioner "ansible" {
    playbook_file          = "${path.root}/../ansible/windows-playbook.yml"
    pause_before           = "45s"
    use_proxy              = false
    user                   = var.windows_winrm_username
    ansible_winrm_use_http = true
    ansible_env_vars = [
      "ANSIBLE_CONFIG=${path.root}/../ansible.cfg",
      "ANSIBLE_REMOTE_TEMP=C:/Windows/Temp/.ansible-osworld",
      "ANSIBLE_REMOTE_TMP=C:/Windows/Temp/.ansible-osworld",
    ]
    extra_arguments = [
      "--extra-vars", "target_platform=windows",
      "--extra-vars", "osworld_user=${var.windows_winrm_username}",
      "--extra-vars", "windows_final_password=${var.windows_final_password}",
      "--extra-vars", "ansible_winrm_transport=ntlm",
      "--extra-vars", "ansible_winrm_scheme=http",
      "--extra-vars", "ansible_winrm_operation_timeout_sec=120",
      "--extra-vars", "ansible_winrm_read_timeout_sec=180",
    ]
  }
}
