#!/usr/bin/python
# -*- coding: utf-8 -*-

from __future__ import annotations

DOCUMENTATION = r"""
---
module: api_key
short_description: Create or revoke a Portainer API token, authenticating with username/password
description:
  - Logs into the Portainer API with a username and password, then creates or revokes a named
    API token (access key) for that user.
  - Portainer only ever returns a token's raw value at creation time. On I(state=present), a
    token is only created if one with the given I(description) doesn't already exist; if it
    does, the module reports no change and no C(api_key) - the raw value isn't recoverable
    through the API after the fact.
options:
  api_url:
    description: Base URL of the Portainer API, e.g. C(https://host:9443/api).
    required: true
    type: str
  username:
    description: Username to authenticate as.
    required: true
    type: str
  password:
    description: Password to authenticate with. Also required by Portainer to confirm token creation.
    required: true
    type: str
    no_log: true
  description:
    description: Description (name) of the API token to create or revoke.
    required: true
    type: str
  validate_certs:
    description: Whether to validate the Portainer API's TLS certificate.
    type: bool
    default: true
  state:
    description: Whether the token should be present or absent.
    type: str
    choices: [present, absent]
    default: present
author:
  - portainer collection maintainers
"""

EXAMPLES = r"""
- name: Create a Portainer API key
  homelab.portainer.api_key:
    api_url: https://127.0.0.1:9443/api
    username: admin
    password: "{{ portainer_password }}"
    description: portainer_setup
    validate_certs: false
  register: key

- name: Revoke it again
  homelab.portainer.api_key:
    api_url: https://127.0.0.1:9443/api
    username: admin
    password: "{{ portainer_password }}"
    description: portainer_setup
    validate_certs: false
    state: absent
"""

RETURN = r"""
api_key:
  description: The token's raw value. Only returned when a new token was just created.
  returned: state=present and a new token was created
  type: str
existed:
  description: Whether a token with this description already existed before this call.
  returned: success
  type: bool
"""

from ansible.module_utils.basic import AnsibleModule
from ansible_collections.homelab.portainer.plugins.module_utils.api.client import PortainerClient, PortainerAPIError
from ansible_collections.homelab.portainer.plugins.module_utils.api.users import find_user_id, find_token, create_token, delete_token


def main():
    module = AnsibleModule(
        argument_spec=dict(
            api_url=dict(type="str", required=True),
            username=dict(type="str", required=True),
            password=dict(type="str", required=True, no_log=True),
            description=dict(type="str", required=True),
            validate_certs=dict(type="bool", default=True),
            state=dict(type="str", choices=["present", "absent"], default="present"),
        ),
        supports_check_mode=True,
    )

    client = PortainerClient(module, module.params["api_url"])

    try:
        client.login(module.params["username"], module.params["password"])
        user_id = find_user_id(client, module.params["username"])
        existing = find_token(client, user_id, module.params["description"])

        if module.params["state"] == "absent":
            if existing is None:
                module.exit_json(changed=False, existed=False)
            if not module.check_mode:
                delete_token(client, user_id, existing["Id"])
            module.exit_json(changed=True, existed=True)

        if existing is not None:
            module.exit_json(changed=False, existed=True)

        if module.check_mode:
            module.exit_json(changed=True, existed=False)

        result = create_token(client, user_id, module.params["description"], module.params["password"])
        module.exit_json(changed=True, existed=False, api_key=result["rawAPIKey"])

    except PortainerAPIError as e:
        module.fail_json(msg=str(e), status=e.status, body=e.body)


if __name__ == "__main__":
    main()
