#!/usr/bin/python
# -*- coding: utf-8 -*-

from __future__ import annotations

DOCUMENTATION = r"""
---
module: validate_credentials
short_description: Check whether a Portainer username/password logs in successfully
description:
  - Logs into the Portainer API with I(username)/I(password) and reports whether that
    succeeded.
  - Read-only: never creates, changes, or removes anything, and always reports C(changed=false).
  - One use is running ahead of the C(homelab.portainer.bootstrap_admin) module, to check whether the
    initial admin account already exists with those exact credentials - so steps only needed
    for first-time setup (like extracting Portainer's setup token from its container logs) can
    be skipped once bootstrapping has already happened.
options:
  api_url:
    description: Base URL of the Portainer API, e.g. C(https://host:9443/api).
    required: true
    type: str
  username:
    description: Username to check.
    required: true
    type: str
  password:
    description: Password to check.
    required: true
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
- name: Check whether the Portainer admin account is already set up
  homelab.portainer.validate_credentials:
    api_url: https://127.0.0.1:9443/api
    username: admin
    password: "{{ portainer_password }}"
    validate_certs: false
  register: portainer_admin
"""

RETURN = r"""
valid:
  description: Whether username/password authenticated successfully against Portainer.
  returned: success
  type: bool
"""

from ansible.module_utils.basic import AnsibleModule
from ansible_collections.homelab.portainer.plugins.module_utils.api.client import PortainerClient
from ansible_collections.homelab.portainer.plugins.module_utils.api.auth import credentials_are_valid


def main():
    module = AnsibleModule(
        argument_spec=dict(
            api_url=dict(type="str", required=True),
            username=dict(type="str", required=True),
            password=dict(type="str", required=True, no_log=True),
            validate_certs=dict(type="bool", default=True),
        ),
        supports_check_mode=True,
    )

    client = PortainerClient(module, module.params["api_url"])
    valid = credentials_are_valid(client, module.params["username"], module.params["password"])
    module.exit_json(changed=False, valid=valid)


if __name__ == "__main__":
    main()
