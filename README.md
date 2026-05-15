# OSWorld Image Builder

English | [中文](README.zh-CN.md)

This repository builds reproducible OSWorld evaluation images from existing OSWorld base images. It does not start from a generic Ubuntu ISO or Canonical AMI. The known-good OSWorld base image is treated as the source of truth, and this project applies only an auditable Packer + Ansible delta.

Supported build targets:

- AWS AMI, derived from `ami-0d23263edb96951d8`
- QEMU qcow2, derived from the OSWorld qcow2 on Hugging Face
- VMware Workstation VM, derived from the OSWorld VMX on Hugging Face

See [docs/usage.md](docs/usage.md) for more detailed usage notes.

## Repository Layout

```text
packer/      Packer builder definitions and variables
ansible/     Shared provisioner playbook and roles
scripts/     Download, preparation, verification, and smoke-test scripts
tests/       In-image smoke checks
docs/        Detailed usage documentation
downloads/   Local download cache, git ignored
build/       Build outputs, git ignored
```

## Prerequisites

The local machine needs:

- `packer`
- `ansible-playbook`
- `aws` CLI and valid AWS credentials
- `qemu-system-x86_64`, `qemu-img`, and KVM access
- `virt-customize`, used to prepare the qcow2 base for SSH
- VMware Workstation and `vmrun`, only for full local VMware testing

Pass sensitive values only through environment variables or ignored local var files. Do not commit AWS keys, SSH passwords, downloaded images, build artifacts, or `.pkrvars.hcl` files.

## Quick Start

Initialize Packer plugins:

```bash
packer init packer
```

Download the Hugging Face base images and generate ignored Packer var files:

```bash
scripts/download-base-images.sh
```

The QEMU base does not expose SSH by default. Prepare an ignored SSH-enabled qcow2 copy first:

```bash
scripts/prepare-qemu-source.sh
```

Run local validation:

```bash
packer validate packer
ansible-playbook --syntax-check ansible/playbook.yml
bash -n scripts/*.sh tests/smoke.sh
```

## AWS Build and Verification

The AWS builder is pinned to the OSWorld base AMI:

```hcl
source_ami = "ami-0d23263edb96951d8"
```

Build the AMI:

```bash
export AWS_REGION=us-east-1
export PKR_VAR_aws_ssh_password='<source-ami-ssh-password>'
packer build -only=aws.amazon-ebs.osworld packer
```

Smoke test the AMI with an existing security group:

```bash
AWS_SMOKE_SECURITY_GROUP_ID=sg-... \
OSWORLD_SSH_PASSWORD='<ami-ssh-password>' \
scripts/smoke-aws.sh ami-...
```

Or let the script create and clean up a temporary security group:

```bash
AWS_SMOKE_ALLOW_TEMP_NETWORK=true \
OSWORLD_SSH_PASSWORD='<ami-ssh-password>' \
scripts/smoke-aws.sh ami-...
```

## QEMU Build and Verification

Build the qcow2:

```bash
export PKR_VAR_ssh_password='<qcow2-ssh-password>'
packer build -only=qemu.qemu.osworld packer
```

Verify the artifact:

```bash
OSWORLD_SSH_PASSWORD='<qcow2-ssh-password>' \
scripts/smoke-qemu.sh build/qemu-osworld-<build-id>/osworld-delta.qcow2 user
```

## VMware Build

The VMware builder derives from the downloaded and extracted `.vmx` file:

```bash
export PKR_VAR_ssh_password='<vm-ssh-password>'
packer build -only=vmware.vmware-vmx.osworld packer
```

Full local VMware smoke testing requires `vmrun`. If VMware Workstation or `vmrun` is unavailable, only builder configuration validation can be completed locally.

## Provisioned Delta

The Ansible playbook installs or verifies these versions:

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

It also configures:

- Chrome Safe Browsing as a no-protection managed policy
- Zotero local communication preferences
- OSWorld server from `https://github.com/adlsdztony/osworld-server`
- `/etc/X11/xorg.conf` with `MaxClients 2048`
- Common office MIME defaults to LibreOffice
- WPS symbol fonts, verified by checksum and `fc-list`

## Smoke Checks

`tests/smoke.sh` checks the following inside the image:

- Application versions or pinned artifact checksums
- Chrome policy
- Zotero preferences
- Xorg `MaxClients`
- LibreOffice MIME defaults
- WPS fonts
- OSWorld server commit marker

`scripts/verify-artifact.sh` is the unified verification entry point:

```bash
scripts/verify-artifact.sh aws ami-...
scripts/verify-artifact.sh qemu build/qemu-osworld-<build-id>/osworld-delta.qcow2 user '<qcow2-ssh-password>'
```

## Local Generated Files

The following paths are generated locally and ignored by git:

- `downloads/`
- `build/`
- `packer/*.auto.pkrvars.hcl`
- `packer/*.pkrvars.hcl`
- `*.qcow2`
- `*.vmdk`
- `*.vmx`
- `*.deb`
- `*.AppImage`
- `*.tar.xz`
- `*.pem`

