# AGENTS.md

## Repo Logic

- `packer/` builds VM artifacts from known OSWorld base images: AWS AMI, QEMU qcow2, and VMware VMX.
- `ansible/playbook.yml` is the shared delta. Roles install pinned apps, configure Chrome/Zotero/defaults/X11, and replace the OSWorld server.
- `ansible/group_vars/all.yml` owns package pins and `osworld_server_commit`. Keep `tests/smoke.sh` and `scripts/smoke-docker-update.sh` in sync with that commit.
- `docker/base/` converts the qcow2 rootfs into `osworld-base-xfce:latest`, removes GNOME/systemd-heavy VM pieces, installs XFCE/supervisor/noVNC, and keeps the original user/server layout.
- `docker/update/` builds `osworld-xfce:latest` from the Docker base by running the same Ansible playbook with `target_platform=docker`.

## Commands

- VM validation: `packer validate packer`, `ansible-playbook --syntax-check ansible/playbook.yml`, `bash -n scripts/*.sh tests/smoke.sh`.
- Docker base: `scripts/build-docker-base.sh`, `scripts/run-docker-base.sh`, `scripts/smoke-docker-base.sh`.
- Docker update: `scripts/build-docker-update.sh`, `scripts/run-docker-update.sh`, `scripts/smoke-docker-update.sh`, then `CONTAINER_NAME=osworld-xfce scripts/smoke-docker-base.sh`.

## Editing Notes

- Docker does not run systemd. Guard VM-only `systemd`/`snapd` behavior with `target_platform | default('') != 'docker'`.
- Docker currently skips snap packages, including Audacity. Use deb/AppImage-style installs if Docker needs those apps.
- Build outputs under `build/`, Docker build cache, temporary containers, and `*:build` images are disposable. `downloads/` is a reusable input cache.
