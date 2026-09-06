# Terraform stacks

Each subdirectory here is a self-contained Terraform root module that
deploys one Docker Compose stack to Portainer, using the
[`portainer/portainer`](https://registry.terraform.io/providers/portainer/portainer/latest)
provider's `portainer_stack` resource. There is no Ansible role for this
anymore - [`../playbooks/portainer_stacks.yml`](../playbooks/portainer_stacks.yml) just runs `terraform
init`/`apply` here directly (via the `terraform` CLI, not an Ansible
Terraform module), from wherever that playbook itself runs.

- [`traefik/`](traefik/)
- [`adguardhome/`](adguardhome/)
- [`homeassistant/`](homeassistant/)
- [`media-stack/`](media-stack/)

## What Terraform does and doesn't own

Terraform owns the whole thing: the rendered Compose content, the stack's
environment variables, *and* the host-side bind-mount directories
referenced by each stack's Compose file (e.g.
`/opt/media-stack/data/qbittorrent`). Each stack's `main.tf` has a
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

## Where host install directories live

Each stack's `variables.tf` declares `install_dir` (this stack's own
directory on the host, e.g. `/opt/adguardhome`) and `volume_mounts`
(bind-mount subdirectories the stack's Compose file needs, keyed by name
and given **relative** to `install_dir`), e.g. ([`adguardhome/variables.tf`](adguardhome/variables.tf)):

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
bind mounts (e.g. `traefik/`) has an empty `volume_mounts` default.

There's no separate config file for these, and no Ansible role either -
`variables.tf` is the single source of truth.

`endpoint_name` and `env` work the same way: left at their `variables.tf`
defaults, or overridden via a real `terraform.tfvars`.

## Running through Ansible (normal path)

`ansible-playbook` [`../playbooks/portainer_stacks.yml`](../playbooks/portainer_stacks.yml) runs, per stack, from
wherever that command itself is invoked (not on the host), via the
`community.general.terraform` module (`force_init: true`, so it handles
`terraform init` for you), passing these as Terraform variables (see
[`../playbooks/portainer_stacks.yml`](../playbooks/portainer_stacks.yml)):
- `portainer_api_url` - `https://<remote_host inventory address>:9443/api`
- `portainer_username`/`portainer_password`/`portainer_api_validate_certs` -
  from [`../group_vars/remote_host/portainer.yml`](../group_vars/remote_host/portainer.yml) (vaulted password)
- `ssh_host`/`ssh_user`/`ssh_private_key_file` - the `remote_host`
  inventory host's address, `ansible_user` and
  `ansible_ssh_private_key_file`, for the `install_dirs` provisioner above

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
the same LAN as the host:

```sh
cd terraform/adguardhome
cp terraform.tfvars.example terraform.tfvars   # fill in real values; never commit it
terraform init
terraform apply
```

Set `portainer_api_url` to the host's LAN address in `terraform.tfvars`
(e.g. `https://192.168.15.15:9443/api`), and `ssh_host`/`ssh_user`/
`ssh_private_key_file` to reach it over SSH - `install_dirs` connects
there regardless of where `terraform apply` itself runs, including when
that's the host itself (in which case `ssh_host` would need to accept a
loopback SSH connection).

## State

Each stack keeps its own local `terraform.tfstate` in its own directory
(no shared backend is configured) - wherever `terraform apply` is run
from, that's where the state lives. Back it up (or move to a remote
backend) if that's not durable enough for you.
