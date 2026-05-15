# OSWorld Delta Image Build

This project starts from known-good OSWorld base images and applies a deterministic delta with Packer and Ansible. It does not start from a generic Ubuntu ISO or AMI.

## Inputs

Use environment variables or ignored local var files for sensitive data. Do not put private credentials in tracked files. The OSWorld public defaults are encoded directly: AWS uses `osworld-public-evaluation`, local VM base images use `password`, and final QEMU/VMware artifacts reset `user` to `osworld-public-evaluation`.

Required before full execution:

- AWS credentials in the environment: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, optional `AWS_SESSION_TOKEN`, and `AWS_REGION` if not using `us-east-1`.
- Confirmation that temporary AWS resources may be created and deleted, or existing `aws_subnet_id` and `aws_security_group_id` values.
- Downloaded OSWorld VMware and qcow2 base images via `scripts/download-base-images.sh`.
- Local QEMU/KVM for the QEMU smoke test.
- VMware Workstation `vmrun` for VMware build testing. The project supports VMware VMX, but this machine currently does not have `vmrun`.

The OSWorld server source is pinned to:

```text
https://github.com/adlsdztony/osworld-server.git
a6979eaf85ce22c281119d2b60e1f25da6dd68ec
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

The default AWS SSH user is `user`, and the default SSH password is the public OSWorld password `osworld-public-evaluation`.
The same value is passed to Ansible as the sudo password through an environment-only password helper.
Set `PKR_VAR_aws_ssh_password` only if the source AMI password differs.

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

The local VM builder defaults to the public base-image password `password`. The QEMU artifact resets `user` to the public OSWorld password `osworld-public-evaluation`; `scripts/smoke-qemu.sh` uses that as its default. Set `PKR_VAR_ssh_password`, `SSH_PORT`, `OSWORLD_SSH_PASSWORD`, or pass SSH user/password arguments only if the source or artifact differs from the defaults.

## VMware Build

```bash
packer build -only=vmware.vmware-vmx.osworld packer
```

The local VM builder defaults to the public source-VM password `password`. The VMware artifact also resets `user` to `osworld-public-evaluation`.

Full VMware testing requires VMware Workstation and `vmrun`.

## Docker XFCE Images

Docker builds are layered:

1. `scripts/build-docker-base.sh` exports the qcow2 rootfs with `guestfish`, imports it as `osworld-rootfs-raw:latest`, removes GNOME/systemd-heavy VM pieces, installs XFCE plus supervisor/noVNC, and writes `osworld-base-xfce:latest`.
2. `scripts/build-docker-update.sh` builds `osworld-xfce:latest` from `osworld-base-xfce:latest`, runs `ansible/playbook.yml` locally with `target_platform=docker`, and flattens the result.

Build and smoke test:

```bash
scripts/build-docker-base.sh
scripts/run-docker-base.sh
scripts/smoke-docker-base.sh

scripts/build-docker-update.sh
scripts/run-docker-update.sh
scripts/smoke-docker-update.sh
CONTAINER_NAME=osworld-xfce scripts/smoke-docker-base.sh
```

Docker does not run systemd, so Ansible tasks guarded by `target_platform=docker` skip snapd, snap packages, and the OSWorld systemd unit. The runtime starts the server through supervisor instead. Keep VM behavior intact when adding Docker guards.

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
