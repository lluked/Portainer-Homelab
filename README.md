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
- [`group_vars/remote_host/`](group_vars/remote_host/) - inventory variables for the host; secrets are
  read from a local HashiCorp Vault (see [Secrets](#secrets)) rather than stored here.
- [`vault/`](vault/) - config template (`config.hcl.tmpl`) and connection
  settings (`vault.env`) for the local HashiCorp Vault server used as this
  repo's secrets backend - see [Secrets](#secrets).
- [`terraform/modules/vault_env/`](terraform/modules/vault_env/) - not a deployable stack; a shared
  Terraform module every stack's `provider.tf` calls to parse
  `vault/vault.env`, so that logic lives in one place - see
  [Secrets](#secrets).
- [`inventory.ini`](inventory.ini) / [`ansible.cfg`](ansible.cfg) - single-host inventory (`remote_host`
  group) and Ansible config (`collections_path = .`, so the vendored
  `homelab.*` collections above are resolved without installing anything).
- [`become_plugins/`](become_plugins/) - a custom `become` plugin (see `ansible.cfg`'s
  `become_plugins` path).
- [`setup.sh`](setup.sh) - creates `inventory.ini` and each stack's
  `plan.auto.tfvars`, and sets up the local Vault (if not already) - see
  [Prerequisites](#prerequisites).

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

Run [`./setup.sh`](setup.sh):

1. Creates [`inventory.ini`](inventory.ini) if it doesn't exist yet,
   prompting for the host's real address/SSH user/SSH key - each defaults
   to [`inventory.ini.example`](inventory.ini.example)'s placeholder value
   if left blank, so press enter three times to accept the example
   verbatim (edit `inventory.ini` afterwards if you do that by mistake).
   Either way, each run also generates a `plan.auto.tfvars` in every
   `terraform/plans/<stack>/` from that entry (see
   [terraform/README.md](terraform/README.md)'s "Running standalone"
   section - not needed for the normal Ansible-driven flow below, only for
   applying a stack's Terraform directly).
2. Starts and, on first run, initializes the local Vault secrets backend
   (see [Secrets](#secrets) below), enables its `kv-v2` engine, and seeds
   `secret/portainer` (prompts for a username/password, defaulting to
   `admin`/a random password if left blank) and `secret/lab` (prompts for
   the lab's base domain, defaulting to `homelab.priv` if left blank).

Safe to re-run any time - each step only does something if it hasn't been
done yet.

## Running it

1. `ansible-playbook` [`playbooks/host_setup.yml`](playbooks/host_setup.yml) - base host setup, then
   installs Docker and Portainer. The admin account and API key are then
   bootstrapped automatically from the Portainer password read out of
   Vault, and the rootless environment registered.
2. `ansible-playbook` [`playbooks/portainer_stacks.yml`](playbooks/portainer_stacks.yml) - deploys the
   Terraform-managed stacks ([`terraform/plans/traefik`](terraform/plans/traefik/), [`terraform/plans/adguardhome`](terraform/plans/adguardhome/),
   [`terraform/plans/homeassistant`](terraform/plans/homeassistant/), ...) to Portainer. Requires a `terraform`
   binary and the `community.general` collection wherever this is run
   from (not vendored here, unlike the `homelab.*` collections). See
   [terraform/README.md](terraform/README.md) for what this actually does
   and how to run a stack standalone instead.

Both playbooks are idempotent and safe to re-run. Some role variables
(`docker_purge_install`, `portainer_purge_install`, the Edge Agent
purge equivalent) are destructive by design and default to `false` -
see each role's `defaults/main.yml` before flipping one on.

## Secrets

Real values (Portainer admin username/password, per-stack secrets) live in
a [HashiCorp Vault](https://www.vaultproject.io/) server running natively
(not in Docker) on **this machine** - the one `ansible-playbook`/
`terraform` are invoked from - never on `remote_host` (the Pi), since the
Portainer password is needed to bootstrap Portainer itself, before
Portainer or Docker exist on the Pi to run anything in.
[`group_vars/remote_host/portainer.yml`](group_vars/remote_host/portainer.yml) reads it via
`community.hashi_vault` lookups, pointed at Vault by
[`hashi_vault.yml`](group_vars/remote_host/hashi_vault.yml) (install that
collection alongside `community.general` - see below);
[`playbooks/portainer_stacks.yml`](playbooks/portainer_stacks.yml) then
passes the resolved `portainer_username`/`portainer_password` through to
each stack's Terraform as ordinary variables. Each `terraform/*/provider.tf`
also reads directly from Vault via the `hashicorp/vault` provider (through
the shared [`terraform/modules/vault_env/`](terraform/modules/vault_env/) module), as a
fallback for whichever of `portainer_username`/`portainer_password` isn't
set - relevant for a standalone Terraform run with no Ansible involved at
all. `lab_domain` (the base domain [`terraform/plans/traefik`](terraform/plans/traefik/)'s router
rule is served under) follows the exact same pattern, one level simpler
(a single value, not a username/password pair): seeded to `secret/lab` in
Vault, read by [`group_vars/remote_host/lab.yml`](group_vars/remote_host/lab.yml), passed through
by `portainer_stacks.yml`, with `terraform/plans/traefik/main.tf` falling
back to Vault directly when unset. Both Ansible and Terraform authenticate to Vault with the root token,
and both get Vault's address the same way: by parsing
[`vault/vault.env`](vault/vault.env) (`VAULT_ADDR` and `VAULT_KEYS_FILE` -
also read by `vault/vault-local.sh`, which sources it directly since
it's a real shell env file), then reading the root token straight out of
whatever `vault/vault.env` names as `VAULT_KEYS_FILE` (`vault/vault_keys.json`
by default) - no environment variable, and no separate scoped-down token,
to manage. Only for a fully standalone Terraform run, with no Vault
involved at all, pass `portainer_username`/`portainer_password`/`env`
directly instead (see the `.example` file in each `terraform/*/`
directory) - both `portainer_username` and `portainer_password` are
optional and fall back to Vault only when unset.

### One-time setup

Install Vault (macOS, via Homebrew):

```sh
brew tap hashicorp/tap
brew install hashicorp/tap/vault
```

Then run [`./setup.sh`](setup.sh) (see [Prerequisites](#prerequisites)) -
it starts Vault (rendering `vault/config.hcl` from `vault/config.hcl.tmpl`
- see `vault/vault-local.sh`), initializes it (`vault operator
init` generates this Vault's unseal keys and root token, which can't be
regenerated - saved to `vault/vault_keys.json`, git-ignored, never commit
it), enables the `kv-v2` secrets engine, and seeds `secret/portainer`
(prompts for a username/password, or generates a random password if left
blank) and `secret/lab` (prompts for the lab's base domain, defaulting to
`homelab.priv` if left blank).

`vault/vault_keys.json` is this setup's equivalent of the old `vault_pass`,
and then some: whoever holds it can unseal Vault, read everything in it,
and - since it holds the root token - do anything else in Vault too
(Ansible and Terraform both authenticate with this same root token, read
straight off this file - see [Secrets](#secrets) above). From here on,
`vault/vault-local.sh start` (which `setup.sh` also calls) reads
it to auto-unseal Vault on every start (see that script for the trust
model this implies).

### Day to day

Before running any playbook or `terraform apply`/`plan`, Vault just needs
to be up and unsealed:

```sh
./vault/vault-local.sh start   # starts + auto-unseals Vault if not already running
```

Nothing else to export - `hashi_vault.yml` and each `terraform/*/provider.tf`
already know where Vault is and read the root token straight out of
`vault/vault_keys.json` (see [Secrets](#secrets) above).
`export VAULT_ADDR=http://127.0.0.1:8200` and
`VAULT_TOKEN=$(jq -r '.root_token' vault/vault_keys.json)` are only needed if you
want to run `vault` CLI commands yourself (`vault kv get`, etc.).

`community.hashi_vault` (the Ansible collection backing the lookups in
`group_vars/remote_host/`) isn't vendored here, same as `community.general`
- install it wherever `ansible-playbook` runs from if it's missing.

### Troubleshooting: "A worker was found in a dead state"

On macOS, Ansible can crash with this error (or a `dial tcp` connection
error to Vault that otherwise looks fine) the first time a play forks
after loading `hvac` (the Vault lookups' Python client) - a known
Python-multiprocessing-vs-Objective-C interaction on macOS, unrelated to
Vault itself. Work around it with:

```sh
export OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES
```
