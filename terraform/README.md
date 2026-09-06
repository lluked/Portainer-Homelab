# Terraform stacks

Each subdirectory under [`plans/`](plans/) is a self-contained Terraform root
module that deploys one Docker Compose stack to Portainer, using the
[`portainer/portainer`](https://registry.terraform.io/providers/portainer/portainer/latest)
provider's `portainer_stack` resource. There is no Ansible role for this
anymore - [`../playbooks/portainer_stacks.yml`](../playbooks/portainer_stacks.yml) just runs `terraform
init`/`apply` here directly (via the `terraform` CLI, not an Ansible
Terraform module), from wherever that playbook itself runs.

- [`plans/traefik/`](plans/traefik/)
- [`plans/traefik-root-discovery/`](plans/traefik-root-discovery/)
- [`plans/adguardhome/`](plans/adguardhome/)
- [`plans/homeassistant/`](plans/homeassistant/)

[`modules/vault_env/`](modules/vault_env/) is not one of these - it's a shared module each
stack's `provider.tf` calls to read the local Vault setup's address and
root token (see [`../README.md`](../README.md)'s "Secrets" section).

## Two Docker daemons, one host: how Traefik sees both

The host runs two separate Docker daemons side by side - a rootless one
(where [`plans/traefik/`](plans/traefik/) deploys) and the root
(rootful) one (where [`plans/adguardhome/`](plans/adguardhome/) and
[`plans/homeassistant/`](plans/homeassistant/) deploy - see each stack's
`endpoint_name` default in its own `variables.tf`). Traefik's Docker
provider can only ever watch one daemon's socket, and it's pointed at the
rootless one it shares with the containers that stack deploys - so on its
own, Traefik never sees `traefik.*` labels on containers running on the
root daemon - both adguardhome and homeassistant have them.

[`plans/traefik-root-discovery/`](plans/traefik-root-discovery/) bridges that gap
without ever handing Traefik (or anything else) direct access to the real
root socket:

- `socket-proxy` (linuxserver/socket-proxy) sits in front of the root
  socket, read-only, restricted to just the container-listing/events
  endpoints Traefik discovery actually needs - never reachable outside an
  `internal: true` network private to this stack.
- `traefik-root-discovery` polls that restricted API, reads the same
  `traefik.*` labels Traefik's own Docker provider would (no relabeling
  needed), and writes them out as a Traefik file-provider dynamic config -
  resolving each service's backend to its already-published host port,
  since a root-daemon container's internal bridge IP isn't reachable from
  the separate rootless daemon Traefik runs on.
- Traefik bind-mounts that output directory read-only and watches it via
  `--providers.file` (see `plans/traefik/variables.tf`'s
  `root_dynamic_config_dir`), alongside its unchanged Docker provider.

`plans/traefik-root-discovery/` has to be applied before `plans/traefik/` (its
output directory needs to already exist) -
[`../playbooks/portainer_stacks.yml`](../playbooks/portainer_stacks.yml) orders it first. A
root-hosted stack only shows up in Traefik once its container's port is
reachable at `root_host_address` - either published to the host directly
(adguardhome) or, for a `network_mode: host` container like homeassistant,
just the port it listens on (Docker reports no port mapping for those,
so `traefik-root-discovery` falls back to the container's declared
`loadbalancer.server.port` directly in that case).

## What Terraform does and doesn't own

Terraform owns the whole thing: the rendered Compose content, the stack's
environment variables, *and* the host-side bind-mount directories
referenced by each stack's Compose file (e.g.
`/opt/adguardhome/work`). Each stack's `main.tf` has a
`null_resource.install_dirs` whose `remote-exec` provisioner runs `sudo
mkdir -p`/`chown` for `install_dir` and every `volume_mounts` entry before
the `portainer_stack` resource (`depends_on`).

That provisioner connects over SSH to `ssh_host` (see below) rather than
running locally, because `terraform apply` is normally invoked from
wherever `ansible-playbook` runs - a workstation, say - not on the host
itself, but the bind-mount directories have to exist on the host regardless
of where `terraform apply` runs. `sudo` because
that SSH user is unprivileged. Docker would otherwise auto-create a
missing bind-mount source directory on container start, but as `root` and
without the ownership these need, which is why they're created ahead of
time instead.

That provisioner only re-runs when `install_dir`/`volume_mounts`
themselves change (Terraform's normal behavior for `null_resource`
triggers) - it won't recreate a directory later removed by hand. Force it
with `terraform apply -replace=null_resource.install_dirs` if that ever
happens.

[`plans/traefik/`](plans/traefik/), [`plans/adguardhome/`](plans/adguardhome/) and
[`plans/homeassistant/`](plans/homeassistant/) also take a `docker_managed_volumes`
variable (default `false`, preserving the bind-mount behavior above). Set
it to `true` to skip `null_resource.install_dirs` entirely and let each
named volume in the stack's Compose file fall back to a plain
Docker-managed volume instead of a host bind mount - `install_dir` and
`volume_mounts` are then unused. Switching
an existing deployment from one mode to the other destroys and recreates
its volumes, so back up first - Docker doesn't migrate data between a
bind mount and a named volume.

[`plans/homeassistant/`](plans/homeassistant/) additionally has a
`null_resource.apparmor_profile`, following the same pattern (SSH to
`ssh_host`, re-runs when its trigger - here a file hash - changes): it
uploads [`plans/homeassistant/apparmor/docker-homeassistant`](plans/homeassistant/apparmor/docker-homeassistant) and loads it with
`apparmor_parser -r`, so the stack's Compose file can reference it via
`security_opt: apparmor=docker-homeassistant` instead of Docker's default
profile, which denies the D-Bus access Home Assistant's Bluetooth
integration needs to reach BlueZ.

## Where host install directories live

Each stack's `variables.tf` declares `install_dir` (this stack's own
directory on the host, e.g. `/opt/adguardhome`) and `volume_mounts`
(bind-mount subdirectories the stack's Compose file needs, keyed by name
and given **relative** to `install_dir`), e.g. ([`plans/adguardhome/variables.tf`](plans/adguardhome/variables.tf)):

```hcl
variable "install_dir" {
  type    = string
  default = "/opt/adguardhome"
}

variable "volume_mounts" {
  type = map(string)
  default = {
    adguardhome_work_dir = "work"
    adguardhome_conf_dir = "conf"
  }
}
```

`main.tf` builds each full path once with plain string interpolation (e.g.
`"${var.install_dir}/${var.volume_mounts["adguardhome_work_dir"]}"`) -
Terraform variable defaults can't reference other variables, so this can't
happen in the variable defaults themselves. The resulting values are
passed into the Compose template under names matching the `volume_mounts`
keys (e.g. `adguardhome_work_dir`), and also drive the
`null_resource.install_dirs` provisioner described above. A stack with no
bind mounts (e.g. `plans/traefik/`) has an empty `volume_mounts` default.

There's no separate config file for these, and no Ansible role either -
`variables.tf` is the single source of truth.

`endpoint_name`, `env` and (where available) `docker_managed_volumes` work
the same way: left at their `variables.tf` defaults, or overridden via a
real `terraform.tfvars`.

## Running through Ansible (normal path)

`ansible-playbook` [`../playbooks/portainer_stacks.yml`](../playbooks/portainer_stacks.yml) runs, per stack, from
wherever that command itself is invoked (not on the host), via the
`community.general.terraform` module (`force_init: true`, so it handles
`terraform init` for you), passing these as Terraform variables (see
[`../playbooks/portainer_stacks.yml`](../playbooks/portainer_stacks.yml)):
- `portainer_api_url` - `https://<remote_host inventory address>:9443/api`
- `portainer_username`/`portainer_password`/`portainer_api_validate_certs` -
  from [`../group_vars/remote_host/portainer.yml`](../group_vars/remote_host/portainer.yml) (the
  first two resolved from Vault there, via `community.hashi_vault` - see
  [`../README.md`](../README.md)'s "Secrets" section)
- `lab_domain` - from [`../group_vars/remote_host/lab.yml`](../group_vars/remote_host/lab.yml) (also resolved
  from Vault, same pattern as `portainer_username`/`portainer_password`
  above). Passed to every stack for consistency, but only
  [`plans/traefik/`](plans/traefik/) actually uses it (its router rule is
  `traefik.<lab_domain>`) - the others declare it in `variables.tf` unused.
- `ssh_host`/`ssh_user`/`ssh_private_key_file` - the `remote_host`
  inventory host's address, `ansible_user` and
  `ansible_ssh_private_key_file`, for the `install_dirs` provisioner above

That `remote_host` host is defined in `../inventory.ini` at the repo root
(gitignored - copy [`../inventory.ini.example`](../inventory.ini.example) to create it):

```ini
[remote_host]
192.168.1.10 ansible_user=admin ansible_ssh_private_key_file=~/.ssh/id_rsa
```

If the Docker host's address, SSH user or key ever changes, update it
there - `portainer_api_url`, `ssh_host`, `ssh_user` and
`ssh_private_key_file` are all derived from this single entry, so nothing
in `terraform/` itself needs touching.

`endpoint_name`, `install_dir`, `volume_mounts` and `env` all come from
each stack's own `variables.tf` defaults by default, but any of them can
also be overridden per stack as extra keys on that stack's entry in
`portainer_stacks.yml`'s `portainer_stacks` list - the intended place for
`env` secrets when running through Ansible, since (unlike a target-side
`terraform.tfvars`) that list can reference vault variables directly.

This requires:
- a `terraform` binary wherever `ansible-playbook` runs this playbook from
- the `community.general` collection there too (not vendored in
  `ansible_collections/` here, unlike the `homelab.*` collections)
- an SSH client, and network access to the host on both 22 (SSH, for
  directory creation) and 9443 (Portainer's API)
- passwordless `sudo` for that SSH user on the host, since
  `null_resource.install_dirs` shells out to `sudo mkdir`/`chown` there

## Running standalone

Each directory can also be applied directly, e.g. from a workstation on
the same LAN as the host. `../../setup.sh` (re-runnable any time
`inventory.ini` changes) generates `portainer_api_url`/`ssh_host`/
`ssh_user`/`ssh_private_key_file` for every stack at once, from
`inventory.ini`'s `[remote_host]` entry, as a git-ignored
`plan.auto.tfvars` in each `terraform/plans/<stack>/` - Terraform loads
`*.auto.tfvars` automatically, so no `-var-file` or manual
`terraform.tfvars` copy is needed for those stacks:

```sh
../../setup.sh   # from any terraform/plans/<stack>/ dir, or just ./setup.sh from the repo root
cd terraform/plans/adguardhome
terraform init
terraform apply
```

`install_dirs` connects to `ssh_host` over SSH regardless of where
`terraform apply` itself runs, including when that's the host itself (in
which case `ssh_host` would need to accept a loopback SSH connection).

To set any of those four by hand instead - e.g. a host not in
`inventory.ini` at all - copy `terraform.tfvars.example` to
`terraform.tfvars` (never committed) and fill it in; explicit
`terraform.tfvars` values there don't override `plan.auto.tfvars` (last
loaded wins, and `*.auto.tfvars` loads after `terraform.tfvars`), so
either don't run `setup.sh` for that stack or remove its
`plan.auto.tfvars` afterwards.

`portainer_username`/`portainer_password` are left commented out in
`terraform.tfvars.example` - by default every stack reads both from
`secret/portainer` in the local HashiCorp Vault instead (see
[`../README.md`](../README.md)'s "Secrets" section and each stack's
`provider.tf`, via the shared [`modules/vault_env/`](modules/vault_env/) module - no
environment variables to export, it parses `../../vault/vault.env` for
Vault's address and where to find the root token). To skip Vault entirely for a
given run, uncomment both in `terraform.tfvars` (or set via `-var`) -
Vault is then never contacted (setting only one still triggers a Vault
read for the other). [`plans/traefik/`](plans/traefik/)'s `lab_domain` works the same
way, falling back to `secret/lab` (field `domain`) when left unset.

## State

Each stack keeps its own local `terraform.tfstate` in its own directory
(no shared backend is configured) - wherever `terraform apply` is run
from, that's where the state lives. Back it up (or move to a remote
backend) if that's not durable enough for you.
