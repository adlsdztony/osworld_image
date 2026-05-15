# OSWorld Image Builder

[English](README.md) | 中文

这个仓库用于从现有 OSWorld 基础镜像出发，复现性地构建带确定性增量配置的评测镜像。它不会从通用 Ubuntu ISO 或 Canonical AMI 重新制作系统，而是把已验证的 OSWorld base image 当作事实源，只在其上应用可审计的 Packer + Ansible delta。

支持的目标产物：

- AWS AMI，基于 `ami-0d23263edb96951d8`
- QEMU qcow2，基于 Hugging Face 上的 OSWorld qcow2
- VMware Workstation VM，基于 Hugging Face 上的 OSWorld VMX

更完整的操作说明见 [docs/usage.md](docs/usage.md)。

## 目录结构

```text
packer/      Packer builder 定义和变量
ansible/     共享 provisioner playbook 与 roles
scripts/     下载、准备、构建验证和 smoke test 脚本
tests/       镜像内 smoke check
docs/        详细使用文档
downloads/   本地下载缓存，git ignored
build/       构建输出，git ignored
```

## 前置条件

本机需要：

- `packer`
- `ansible-playbook`
- `aws` CLI 和有效 AWS 凭证
- `qemu-system-x86_64`、`qemu-img`、KVM 权限
- `virt-customize`，用于给 qcow2 base 准备 SSH
- VMware Workstation 和 `vmrun`，仅在需要完整 VMware 本地测试时使用

敏感信息只通过环境变量或 ignored var 文件传入。不要把 AWS key、SSH 密码、下载的镜像、构建产物或 `.pkrvars.hcl` 提交进仓库。

## 快速开始

初始化 Packer 插件：

```bash
packer init packer
```

下载 Hugging Face base image，并生成 ignored Packer var 文件：

```bash
scripts/download-base-images.sh
```

QEMU base 默认不暴露 SSH，需要先准备一个 ignored 的 SSH-enabled qcow2 副本：

```bash
scripts/prepare-qemu-source.sh
```

本地校验：

```bash
packer validate packer
ansible-playbook --syntax-check ansible/playbook.yml
bash -n scripts/*.sh tests/smoke.sh
```

## AWS 构建和验证

AWS builder 固定使用 OSWorld base AMI：

```hcl
source_ami = "ami-0d23263edb96951d8"
```

构建 AMI：

```bash
export AWS_REGION=us-east-1
export PKR_VAR_aws_ssh_password='<source-ami-ssh-password>'
packer build -only=aws.amazon-ebs.osworld packer
```

Smoke test AMI。可以提供已有 security group：

```bash
AWS_SMOKE_SECURITY_GROUP_ID=sg-... \
OSWORLD_SSH_PASSWORD='<ami-ssh-password>' \
scripts/smoke-aws.sh ami-...
```

也可以让脚本创建并清理临时 security group：

```bash
AWS_SMOKE_ALLOW_TEMP_NETWORK=true \
OSWORLD_SSH_PASSWORD='<ami-ssh-password>' \
scripts/smoke-aws.sh ami-...
```

## QEMU 构建和验证

构建 qcow2：

```bash
export PKR_VAR_ssh_password='<qcow2-ssh-password>'
packer build -only=qemu.qemu.osworld packer
```

验证产物：

```bash
OSWORLD_SSH_PASSWORD='<qcow2-ssh-password>' \
scripts/smoke-qemu.sh build/qemu-osworld-<build-id>/osworld-delta.qcow2 user
```

## VMware 构建

VMware builder 从下载解压出的 `.vmx` 派生：

```bash
export PKR_VAR_ssh_password='<vm-ssh-password>'
packer build -only=vmware.vmware-vmx.osworld packer
```

完整 VMware 本地 smoke test 需要 `vmrun`。如果当前机器没有 VMware Workstation 或 `vmrun`，只能验证 builder 配置，不能完成本地运行测试。

## 应用增量

Ansible playbook 会安装或验证以下版本：

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

同时会配置：

- Chrome Safe Browsing 为 no protection managed policy
- Zotero 本机通信设置
- OSWorld server，固定到 `https://github.com/adlsdztony/osworld-server`
- `/etc/X11/xorg.conf` 的 `MaxClients 2048`
- 常见 office MIME 类型默认使用 LibreOffice
- WPS symbol fonts，并通过 checksum 和 `fc-list` 验证

## Smoke Check

`tests/smoke.sh` 会在镜像内检查：

- 应用版本或 pinned artifact checksum
- Chrome policy
- Zotero preference
- Xorg `MaxClients`
- LibreOffice MIME defaults
- WPS fonts
- OSWorld server commit marker

`scripts/verify-artifact.sh` 是统一入口：

```bash
scripts/verify-artifact.sh aws ami-...
scripts/verify-artifact.sh qemu build/qemu-osworld-<build-id>/osworld-delta.qcow2 user '<qcow2-ssh-password>'
```

## 本地生成文件

以下路径通常是构建副产物，已通过 `.gitignore` 排除：

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

