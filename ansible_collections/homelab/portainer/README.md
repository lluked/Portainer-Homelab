# homelab.portainer

Ansible collection of custom modules for driving the Portainer API
directly - bootstrapping and environment/token management that isn't
covered by any upstream Ansible collection. Used by the `homelab.host_setup`
collection's `portainer` role (see
[`../host_setup/README.md`](../host_setup/README.md)) and by
[`playbooks/portainer_stacks.yml`](../../../playbooks/portainer_stacks.yml)
for the Portainer connection details Terraform needs.

Resolved via `collections_path = .` in
[`ansible.cfg`](../../../ansible.cfg) - no separate install step needed
from this repo.

## Modules

- **`validate_credentials`** - logs in with a username/password and
  reports whether it succeeded. Read-only, always `changed=false`. Used to
  check up front whether the admin account already exists with the given
  credentials, so first-time-only setup steps can be skipped once
  bootstrapping has already happened.
- **`bootstrap_admin`** - calls Portainer's `/users/admin/init` endpoint to
  create the initial admin account non-interactively, instead of going
  through the setup wizard. Requires the one-time setup token Portainer
  prints to its own container logs on startup (expires after 5 minutes or
  first use) for the very first call; later calls get `409` (already
  initialized), treated as success/no-change.
- **`api_key`** - logs in with username/password and creates or revokes a
  named API token. A token's raw value is only ever returned at creation
  time - if one with the given description already exists, this reports no
  change and no `api_key` (the value isn't recoverable from the API after
  the fact).
- **`environment`** - creates or removes a Portainer environment
  (endpoint), identified by name. Supports a `local` environment (Unix
  socket reachable directly from inside the Portainer container) and an
  `edge` environment (reverse tunnel dialed back in by a Portainer Edge
  Agent) - `edge` is required for any Docker host/socket that isn't the
  one Portainer itself has bind-mounted access to, since Portainer's stack
  deployment engine only targets its own local socket.

Each module's `DOCUMENTATION`/`EXAMPLES` (in [`plugins/modules/`](plugins/modules/)) is the
authoritative reference for its options - this is a summary of intent, not
a substitute for those.

## Supporting code

[`plugins/module_utils/api/`](plugins/module_utils/api/) holds the shared HTTP client ([`client.py`](plugins/module_utils/api/client.py)) and
thin per-resource wrappers ([`auth.py`](plugins/module_utils/api/auth.py), [`users.py`](plugins/module_utils/api/users.py), [`endpoints.py`](plugins/module_utils/api/endpoints.py),
[`endpoint_groups.py`](plugins/module_utils/api/endpoint_groups.py)) that the modules above are built on.
