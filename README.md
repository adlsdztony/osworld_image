# OSWorld Image Builder

English | [中文](README.zh-CN.md)

This repository builds reproducible OSWorld evaluation images from existing OSWorld base images. It does not start from a generic Ubuntu ISO or Canonical AMI. The known-good OSWorld base image is treated as the source of truth, and this project applies only an auditable Packer + Ansible delta.

Supported build targets:

- AWS AMI, derived from `ami-0d23263edb96951d8`
- QEMU qcow2, derived from the OSWorld qcow2 on Hugging Face
- VMware Workstation VM, derived from the OSWorld VMX on Hugging Face
- Docker XFCE base image, derived from the OSWorld qcow2 rootfs
- Docker XFCE update image, derived from the Docker base image and the same Ansible delta

See [docs/usage.md](docs/usage.md) for more detailed usage notes.

## Repository Layout

```text
packer/      Packer builder definitions and variables
ansible/     Shared provisioner playbook and roles
docker/      Docker base and update image definitions
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
- `docker`, `guestfish`, and `qemu-img` for Docker rootfs migration
- VMware Workstation and `vmrun`, only for full local VMware testing

Pass sensitive values only through environment variables or ignored local var files. Do not commit AWS keys, private SSH passwords, downloaded images, build artifacts, or `.pkrvars.hcl` files. The OSWorld public defaults are encoded directly: AWS uses `osworld-public-evaluation`, local VM base images use `password`, and final QEMU/VMware artifacts reset `user` to `osworld-public-evaluation`.

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
packer build -only=aws.amazon-ebs.osworld packer
```

Override `PKR_VAR_aws_ssh_password` only if the source AMI password differs from the public default.

Smoke test the AMI with an existing security group:

```bash
AWS_SMOKE_SECURITY_GROUP_ID=sg-... \
scripts/smoke-aws.sh ami-...
```

Or let the script create and clean up a temporary security group:

```bash
AWS_SMOKE_ALLOW_TEMP_NETWORK=true \
scripts/smoke-aws.sh ami-...
```

## QEMU Build and Verification

Build the qcow2:

```bash
packer build -only=qemu.qemu.osworld packer
```

The local VM builder defaults to the public base-image password `password`. Override `PKR_VAR_ssh_password` only if the source qcow2 password differs.

The QEMU artifact resets the `user` password to the public OSWorld password: `osworld-public-evaluation`.

Verify the artifact:

```bash
scripts/smoke-qemu.sh build/qemu-osworld-<build-id>/osworld-delta.qcow2 user
```

## VMware Build

The VMware builder derives from the downloaded and extracted `.vmx` file:

```bash
packer build -only=vmware.vmware-vmx.osworld packer
```

The local VM builder defaults to the public source-VM password `password`. Override `PKR_VAR_ssh_password` only if the source VM password differs.

The VMware artifact also resets the `user` password to `osworld-public-evaluation`.

Full local VMware smoke testing requires `vmrun`. If VMware Workstation or `vmrun` is unavailable, only builder configuration validation can be completed locally.

## Docker Build and Verification

The Docker flow has two stages. The base stage imports the qcow2 rootfs, removes VM-only/GNOME/systemd pieces, installs XFCE plus supervisor/noVNC, and keeps the original desktop user and server layout. The update stage starts from that base and runs the same Ansible delta with `target_platform=docker`.

Build and run the Docker base image:

```bash
scripts/build-docker-base.sh
scripts/run-docker-base.sh
scripts/smoke-docker-base.sh
```

Build and run the updated Docker image:

```bash
scripts/build-docker-update.sh
scripts/run-docker-update.sh
scripts/smoke-docker-update.sh
CONTAINER_NAME=osworld-xfce scripts/smoke-docker-base.sh
```

Docker intentionally skips snapd/snap packages because the image does not run systemd. If Audacity is required in Docker, add a deb/AppImage-style install path instead of re-enabling snapd.

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
- QEMU and VMware `user` password set to `osworld-public-evaluation`
- Docker runtime uses supervisor to start DBus, Xvfb, XFCE, x11vnc/noVNC, and the OSWorld server

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
scripts/verify-artifact.sh qemu build/qemu-osworld-<build-id>/osworld-delta.qcow2 user
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
