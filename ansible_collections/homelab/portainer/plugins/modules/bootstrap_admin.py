#!/usr/bin/python
# -*- coding: utf-8 -*-

from __future__ import annotations

DOCUMENTATION = r"""
---
module: bootstrap_admin
short_description: Create Portainer's initial admin account
description:
  - Calls Portainer's C(/users/admin/init) endpoint to create the initial admin account,
    so the whole setup can run unattended instead of going through the setup wizard.
  - Portainer returns C(200) the first time (account created) and C(409) on every later call
    (already initialized) - both are treated as success, with C(409) reported as no change,
    which is what makes this safe to run repeatedly.
  - Since Portainer 2.20, that first call also requires a one-time setup token that Portainer
    prints to its own container logs on startup and that expires after 5 minutes or first use
    (see I(setup_token)). On later, already-initialized calls it's fine for this to be omitted
    or stale - Portainer returns C(409) before it ever checks the token.
  - See the C(homelab.portainer.validate_credentials) module to check beforehand whether this even
    needs calling - e.g. to skip extracting that setup token when it doesn't.
options:
  api_url:
    description: Base URL of the Portainer API, e.g. C(https://host:9443/api).
    required: true
    type: str
  username:
    description: Username to give the initial admin account.
    required: true
    type: str
  password:
    description: Password to give the initial admin account.
    required: true
    type: str
    no_log: true
  setup_token:
    description:
      - The one-time setup token Portainer printed to its container logs on startup
        (as C(setup_token=<value>)), sent as the C(X-Setup-Token) header.
      - Only required for the first, account-creating call - see the description above.
    type: str
    no_log: true
  validate_certs:
    description: Whether to validate the Portainer API's TLS certificate.
    type: bool
    default: true
author:
  - portainer collection maintainers
"""

EXAMPLES = r"""
- name: Create the initial Portainer admin account
  homelab.portainer.bootstrap_admin:
    api_url: https://127.0.0.1:9443/api
    username: admin
    password: "{{ portainer_password }}"
    setup_token: "{{ _portainer_setup_token }}"
    validate_certs: false
"""

RETURN = r"""
status:
  description: HTTP status code returned by the Portainer API (200 if created, 409 if already initialized).
  returned: success
  type: int
"""

from ansible.module_utils.basic import AnsibleModule
from ansible_collections.homelab.portainer.plugins.module_utils.api.client import PortainerClient, PortainerAPIError
from ansible_collections.homelab.portainer.plugins.module_utils.api.users import init_admin


def main():
    module = AnsibleModule(
        argument_spec=dict(
            api_url=dict(type="str", required=True),
            username=dict(type="str", required=True),
            password=dict(type="str", required=True, no_log=True),
            setup_token=dict(type="str", no_log=True),
            validate_certs=dict(type="bool", default=True),
        ),
        supports_check_mode=True,
    )

    if module.check_mode:
        module.exit_json(changed=True, status=None)

    client = PortainerClient(module, module.params["api_url"])

    try:
        status = init_admin(
            client,
            module.params["username"],
            module.params["password"],
            module.params["setup_token"],
        )
        module.exit_json(changed=status == 200, status=status)

    except PortainerAPIError as e:
        module.fail_json(msg=str(e), status=e.status, body=e.body)


if __name__ == "__main__":
    main()
