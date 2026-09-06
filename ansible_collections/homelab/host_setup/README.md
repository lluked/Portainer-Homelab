# homelab.host_setup

Ansible collection that provisions the host itself: base OS setup, Docker
(rootful and rootless, side by side), and Portainer.

Used by [`playbooks/host_setup.yml`](../../../playbooks/host_setup.yml) (see
the repo's top-level README for the overall setup flow). Resolved via
`collections_path = .` in [`ansible.cfg`](../../../ansible.cfg), so no
separate install step is needed to use it from this repo.

## Roles

### `system`

Base host prep: package updates, and two opt-in tweaks controlled by
[`roles/system/defaults/main.yml`](roles/system/defaults/main.yml):

- `system_disable_resolved_stub_listener` (default `true`) - disables
  systemd-resolved's DNS stub listener on `127.0.0.53:53` so a container
  (e.g. AdGuard Home) can bind port 53 itself.
- `system_bluetooth_setup` (default `true`) - installs `bluez`/
  `bluez-tools`.

### `docker`

Installs Docker CE with **both** a rootful and a rootless engine running
side by side, each registered as a Docker context (`root` / `rootless`,
see `docker_contexts` in [`roles/docker/defaults/main.yml`](roles/docker/defaults/main.yml)) so either can be targeted
with `docker --context <name>` or `docker context use <name>`. Exactly one
context must be marked `default: true`; the role asserts this up front.

`docker_purge_install` (default `false`) wipes every container and volume
on every context before reinstalling - destructive, off by default, meant
for a deliberate one-off reset. A normal run just stops running containers
before reinstalling packages.

### `portainer`

Installs Portainer CE on the rootful docker context, then uses the
`homelab.portainer` collection's custom modules to:

- bootstrap the initial admin account (`portainer_username`/
  `portainer_password`, both blank by default so a fresh install still
  succeeds without them),
- generate/reuse a `portainer_api_key`,
- register the rootful context as Portainer's local environment, and
- deploy a Portainer Edge Agent onto every other context in
  `portainer_docker_contexts` (e.g. `rootless`) and register each as an
  Edge environment - Portainer's stack deployment only works against its
  own local socket, not a second bind-mounted one, hence the Edge Agent
  for anything else.

`portainer_purge_install` (default `false`) tears down any existing
Portainer stack and deletes its `portainer_data` volume (all users,
settings, registered environments) before recreating it - destructive, off
by default.

See each role's `defaults/main.yml` for the full set of variables and the
reasoning behind them - they're documented inline.
