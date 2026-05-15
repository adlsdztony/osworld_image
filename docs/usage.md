# OSWorld Delta Image Build

This project starts from known-good OSWorld base images and applies a deterministic delta with Packer and Ansible. It does not start from a generic Ubuntu ISO or AMI.

## Inputs

Use environment variables or ignored local var files for sensitive data. Do not put credentials in tracked files.

Required before full execution:

- AWS credentials in the environment: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, optional `AWS_SESSION_TOKEN`, and `AWS_REGION` if not using `us-east-1`.
- Confirmation that temporary AWS resources may be created and deleted, or existing `aws_subnet_id` and `aws_security_group_id` values.
- Downloaded OSWorld VMware and qcow2 base images via `scripts/download-base-images.sh`.
- Local QEMU/KVM for the QEMU smoke test.
- VMware Workstation `vmrun` for VMware build testing. The project supports VMware VMX, but this machine currently does not have `vmrun`.

The OSWorld server source is pinned to:

```text
https://github.com/adlsdztony/osworld-server.git
8bb13c5315392e2500f9a27013285bbc375b2c3a
```

## Base Images

Download and inspect the Hugging Face base images:

```bash
scripts/download-base-images.sh
```

The script writes `packer/base-images.auto.pkrvars.hcl`, which is ignored by git. It points Packer at the discovered `.vmx` and `.qcow2` paths, records the qcow2 checksum, and caches the checksum-verified WPS symbol font ZIP under ignored `downloads/wps_fonts/`. Run `scripts/download-wps-fonts.sh` directly if only that font asset needs refreshing.

The qcow2 base does not expose SSH by default. Prepare an ignored SSH-enabled qcow2 copy before the QEMU Packer build:

```bash
scripts/prepare-qemu-source.sh
```

## Local Validation

```bash
packer init packer
packer validate packer
ansible-playbook --syntax-check ansible/playbook.yml
```

## AWS AMI Build

The AWS builder uses:

```hcl
source_ami = "ami-0d23263edb96951d8"
```

Run after credentials and network choices are confirmed:

```bash
packer build -only=aws.amazon-ebs.osworld packer
```

The default AWS SSH user is `user`. Set `PKR_VAR_aws_ssh_password` in the environment when the source AMI uses password login.
The same value is passed to Ansible as the sudo password through an environment-only password helper.

If using existing network resources, put non-secret values in an ignored var file such as `packer/local.auto.pkrvars.hcl`:

```hcl
aws_subnet_id = "subnet-..."
aws_security_group_id = "sg-..."
```

Smoke test the AMI:

```bash
AWS_SMOKE_SECURITY_GROUP_ID=sg-... scripts/smoke-aws.sh ami-...
```

To let the script create and delete a temporary security group:

```bash
AWS_SMOKE_ALLOW_TEMP_NETWORK=true scripts/smoke-aws.sh ami-...
```

## QEMU qcow2 Build

```bash
packer build -only=qemu.qemu.osworld packer
scripts/smoke-qemu.sh build/qemu-osworld-<build-id>/osworld-delta.qcow2
```

Set `SSH_PORT`, `OSWORLD_SSH_PASSWORD`, or pass SSH user/password arguments, if the base image differs from the defaults.

## VMware Build

```bash
packer build -only=vmware.vmware-vmx.osworld packer
```

Full VMware testing requires VMware Workstation and `vmrun`.

## Software Delta

The playbook installs or verifies these versions:

- Obsidian `1.10.6`
- Audacity `3.7.5`
- Shotcut `26.2.26`
- XMind `26.01.03145`
- Zotero `8.0.2`
- LabPlot `2.12.1`
- Blender `5.0.0`
- WPS Office `11.1.0.11723`
- REAPER `7.64`
- MuseScore `4.6`

Several requested snap versions are no longer current in the snap store, so those applications use pinned upstream deb/AppImage/tar artifacts with checksum gates. MuseScore 3 is intentionally not installed; no evidence in this repo shows that it is required by OSWorld tasks.

The WPS symbol fonts use the `owlman/wps_fonts` archive at commit `89beda2cf241c4524a5926bf13c92bdc8a73e9d0`, matching the font set referenced by the requested WPS font instructions.

## Smoke Checks

`tests/smoke.sh` verifies:

- Requested application versions or pinned checksums.
- Chrome Safe Browsing managed policy set to no protection.
- Zotero local communication preferences.
- Xorg `MaxClients` set to `2048`.
- LibreOffice MIME defaults for common office files.
- WPS symbol fonts visible to `fc-list`.
- OSWorld server commit marker.
