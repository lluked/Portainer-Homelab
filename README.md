# Portainer Homelab

Ansible + Terraform setup for a single host running Docker (rootful
and rootless, side by side) managed through Portainer, with app stacks
deployed as Portainer stacks via Terraform.

Tested on a Raspberry Pi running Ubuntu 26.04.01 LTS, with Portainer CE
2.45.0 and the Portainer Edge Agent 2.45.0 (both `portainer_image` and
`portainer_edge_agent_image` default to their `:latest` tag - see
[`ansible_collections/homelab/host_setup/roles/portainer/defaults/main.yml`](ansible_collections/homelab/host_setup/roles/portainer/defaults/main.yml)).

## Layout

- [`ansible_collections/homelab/host_setup/`](ansible_collections/homelab/host_setup/) - roles that provision the
  host itself: base host setup, Docker (rootful + rootless), and Portainer
  (including registering the rootless engine as a second environment via
  Edge Agent).
- [`ansible_collections/homelab/portainer/`](ansible_collections/homelab/portainer/) - custom Ansible modules used by
  the `host_setup` collection's `portainer` role to drive Portainer's API
  directly (bootstrapping the admin account, creating API keys, registering
  environments) - none of this is available as upstream Ansible modules.
- [`playbooks/`](playbooks/) - entry points that consume the collections above.
- [`terraform/`](terraform/) - one root module per app stack, each deploying a Docker
  Compose stack to Portainer via the `portainer_stack` resource. See
  [terraform/README.md](terraform/README.md).
- [`group_vars/remote_host/`](group_vars/remote_host/) - inventory variables for the host, including a
  vaulted `vault.yml`.
- [`inventory.ini`](inventory.ini) / [`ansible.cfg`](ansible.cfg) - single-host inventory (`remote_host`
  group) and Ansible config (`collections_path = .`, so the vendored
  `homelab.*` collections above are resolved without installing anything).
- [`become_plugins/`](become_plugins/) - a custom `become` plugin (see `ansible.cfg`'s
  `become_plugins` path).

## `become_plugins` (sudo-rs fix)

Ubuntu 24.04+ (including the 26.04 host this is tested on) ships `sudo-rs`
instead of GNU sudo. Upstream `ansible-core` (as of 2.21.3) fails privilege
escalation against it, because `sudo-rs` wraps Ansible's custom `-p` prompt in
its own `[sudo: ...] Password:` text instead of replacing it outright, and
`check_password_prompt()` only matches an exact prefix.
[`become_plugins/sudo.py`](become_plugins/sudo.py) is a vendored copy of the
builtin `sudo` become plugin with the fix from
[ansible/ansible#86175](https://github.com/ansible/ansible/pull/86175)
applied, auto-discovered by Ansible to shadow the builtin plugin for this
project only (see `ansible.cfg`'s `become_plugins` path).

That PR has merged to `devel` but has no released `ansible-core` version yet
(its stable backports were reverted) - once a released `ansible-core` version
includes the fix, this vendored plugin (and the `become_plugins` path in
[`ansible.cfg`](ansible.cfg)) should be removed.

## Prerequisites

Set up the vault - create `group_vars/remote_host/vault.yml` and set
`vault_portainer_password` in it, as described under
[Creating `vault.yml`](#creating-vaultyml) below.

## Running it

1. `ansible-playbook` [`playbooks/host_setup.yml`](playbooks/host_setup.yml) - base host setup, then
   installs Docker and Portainer. The admin account and API key are then
   bootstrapped automatically from `vault_portainer_password`, and the
   rootless environment registered.
2. `ansible-playbook` [`playbooks/portainer_stacks.yml`](playbooks/portainer_stacks.yml) - deploys the
   Terraform-managed stacks ([`terraform/traefik`](terraform/traefik/), [`terraform/adguardhome`](terraform/adguardhome/),
   [`terraform/homeassistant`](terraform/homeassistant/), ...) to Portainer. Requires a `terraform`
   binary and the `community.general` collection wherever this is run
   from (not vendored here, unlike the `homelab.*` collections). See
   [terraform/README.md](terraform/README.md) for what this actually does
   and how to run a stack standalone instead.

Both playbooks are idempotent and safe to re-run. Some role variables
(`docker_purge_install`, `portainer_purge_install`, the Edge Agent
purge equivalent) are destructive by design and default to `false` -
see each role's `defaults/main.yml` before flipping one on.

## Secrets

Real values (Portainer admin password, API key, per-stack secrets) live in
[`group_vars/remote_host/vault.yml`](group_vars/remote_host/vault.yml), encrypted with `ansible-vault` and
decrypted via `vault_password_file` in [`ansible.cfg`](ansible.cfg) (kept out of git, see
[`.gitignore`](.gitignore)). Only for a fully standalone Terraform run, with no Ansible
involved at all, do secrets go directly in that stack's `terraform.tfvars`
(see the `.example` file in each `terraform/*/` directory) instead.

### Creating `vault.yml`

`vault_password_file = ./vault_pass` in [`ansible.cfg`](ansible.cfg) means Ansible
expects the vault password in a file named `vault_pass` in the repo root
(git-ignored - never commit it):

```sh
echo 'your-vault-password-here' > vault_pass
chmod 600 vault_pass
```

Then create the vault file itself:

```sh
ansible-vault create group_vars/remote_host/vault.yml
```

This opens `$EDITOR` with the file transparently decrypted; fill in the
variables referenced elsewhere under `group_vars/remote_host/` (e.g.
[`portainer.yml`](group_vars/remote_host/portainer.yml)) and save:

```yaml
vault_portainer_password: "..."
```

To edit it again later (still using `vault_pass` from the repo root
automatically): `ansible-vault edit group_vars/remote_host/vault.yml`.
