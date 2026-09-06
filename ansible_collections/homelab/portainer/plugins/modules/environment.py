#!/usr/bin/python
# -*- coding: utf-8 -*-

from __future__ import annotations

DOCUMENTATION = r"""
---
module: environment
short_description: Create or remove a Portainer environment (endpoint) backed by a local docker socket
description:
  - Registers (or removes) a Portainer "environment" - what Portainer calls a Docker endpoint.
  - Two kinds are supported. A C(local) environment is connected via a Unix socket that's
    reachable from inside the Portainer container itself (typically a bind-mounted socket).
    An C(edge) environment is connected via a reverse tunnel that a Portainer Edge Agent
    running elsewhere dials back in on - use this for any Docker host/socket that isn't the
    one Portainer's own container has direct bind-mounted access to, since Portainer's stack
    deployment engine only works against its own local socket, not a second bind-mounted one
    registered as another local environment.
  - Identifies the environment by I(name). If one with that name already exists, this module
    leaves it untouched (its URL/type is not checked or updated) and reports no change - it's
    meant for environments this creates itself, not for adopting or reconciling ones set up
    another way (e.g. Portainer's own "local" environment from the setup wizard).
options:
  api_url:
    description: Base URL of the Portainer API, e.g. C(https://host:9443/api).
    required: true
    type: str
  api_key:
    description: Portainer API key (generate one under your user icon -> "API keys", or see the
      C(homelab.portainer.api_key) module).
    required: true
    type: str
    no_log: true
  validate_certs:
    description: Whether to validate the Portainer API's TLS certificate.
    type: bool
    default: true
  name:
    description: Name of the environment.
    required: true
    type: str
  type:
    description:
      - C(local) registers a Unix-socket-backed environment (I(url) required).
      - C(edge) registers an Edge Agent environment (I(url) required) - the returned/existing
        environment's Edge key is available as I(edge_key) so it can be handed to the actual
        Edge Agent container, and its Edge ID as I(endpoint.EdgeID).
    type: str
    choices: [local, edge]
    default: local
  url:
    description:
      - For I(type=local), the Docker endpoint URL, e.g. C(unix:///var/run/docker.sock) -
        must be reachable from inside the Portainer container (a bind-mounted socket,
        typically).
      - For I(type=edge), Portainer's own base URL as reachable by the Edge Agent, e.g.
        C(https://192.168.1.50:9443) - this gets embedded in the generated Edge key so the
        agent knows where to poll/tunnel back to. Only the hostname is used (the reverse
        tunnel itself always connects to Portainer's own configured tunnel server port, e.g.
        I(portainer_edge_tunnel_port)), but the scheme is required for Portainer to parse it.
      - Required when I(state=present).
    type: str
  group:
    description:
      - Name of the Portainer environment group to place a newly created environment in.
      - The group is looked up by name and created if it doesn't already exist yet.
      - Only applied when the environment itself is being created - like I(name), an
        already-existing environment is left untouched and is not moved into the group.
      - When omitted, Portainer places the environment in its default "Unassigned" group.
    type: str
  state:
    description: Whether the environment should be present or absent.
    type: str
    choices: [present, absent]
    default: present
author:
  - portainer collection maintainers
"""

EXAMPLES = r"""
- name: Register the root docker engine as a local Portainer environment
  homelab.portainer.environment:
    api_url: https://127.0.0.1:9443/api
    api_key: "{{ portainer_api_key }}"
    validate_certs: false
    name: root
    type: local
    url: unix:///var/run/docker.sock

- name: Register the rootless docker engine as an Edge Portainer environment
  homelab.portainer.environment:
    api_url: https://127.0.0.1:9443/api
    api_key: "{{ portainer_api_key }}"
    validate_certs: false
    name: rootless
    type: edge
    url: https://192.168.1.50:9443
  register: rootless_endpoint

- name: Register an environment and place it in a group, creating the group if needed
  homelab.portainer.environment:
    api_url: https://127.0.0.1:9443/api
    api_key: "{{ portainer_api_key }}"
    validate_certs: false
    name: rootless
    type: edge
    url: https://192.168.1.50:9443
    group: homelab

- name: Remove it
  homelab.portainer.environment:
    api_url: https://127.0.0.1:9443/api
    api_key: "{{ portainer_api_key }}"
    validate_certs: false
    name: rootless
    state: absent
"""

RETURN = r"""
endpoint:
  description: The environment object returned by the Portainer API after creation (empty when removed, already absent, or already present).
  returned: success
  type: dict
edge_key:
  description: The environment's Edge key, for handing to its Edge Agent container. Empty for C(local) environments.
  returned: success
  type: str
"""

from ansible.module_utils.basic import AnsibleModule
from ansible_collections.homelab.portainer.plugins.module_utils.api.client import PortainerClient, PortainerAPIError
from ansible_collections.homelab.portainer.plugins.module_utils.api.endpoints import find_endpoint, create_endpoint, delete_endpoint
from ansible_collections.homelab.portainer.plugins.module_utils.api.endpoint_groups import find_group, create_group


def main():
    module = AnsibleModule(
        argument_spec=dict(
            api_url=dict(type="str", required=True),
            api_key=dict(type="str", required=True, no_log=True),
            validate_certs=dict(type="bool", default=True),
            name=dict(type="str", required=True),
            type=dict(type="str", choices=["local", "edge"], default="local"),
            url=dict(type="str"),
            group=dict(type="str"),
            state=dict(type="str", choices=["present", "absent"], default="present"),
        ),
        supports_check_mode=True,
    )

    if module.params["state"] == "present" and not module.params["url"]:
        module.fail_json(msg="url is required when state=present")

    client = PortainerClient(
        module,
        module.params["api_url"],
        headers={"X-API-Key": module.params["api_key"], "Content-Type": "application/json"},
    )

    try:
        existing = find_endpoint(client, module.params["name"])

        if module.params["state"] == "absent":
            if existing is None:
                module.exit_json(changed=False, endpoint={}, edge_key="")
            if not module.check_mode:
                delete_endpoint(client, existing["Id"])
            module.exit_json(changed=True, endpoint={}, edge_key="")

        if existing is not None:
            module.exit_json(changed=False, endpoint=existing, edge_key=existing.get("EdgeKey", ""))

        group_id = None
        if module.params["group"]:
            group = find_group(client, module.params["group"])
            if group is None and not module.check_mode:
                group = create_group(client, module.params["group"])
            if group is not None:
                group_id = group["Id"]

        if module.check_mode:
            module.exit_json(changed=True, endpoint={}, edge_key="")

        creation_type = "1" if module.params["type"] == "local" else "4"
        fields = {"EndpointCreationType": creation_type, "URL": module.params["url"]}
        if module.params["type"] == "edge":
            fields["ContainerEngine"] = "docker"
        if group_id is not None:
            fields["GroupID"] = group_id

        endpoint = create_endpoint(client, module.params["name"], fields)
        module.exit_json(changed=True, endpoint=endpoint, edge_key=endpoint.get("EdgeKey", ""))

    except PortainerAPIError as e:
        module.fail_json(msg=str(e), status=e.status, body=e.body)


if __name__ == "__main__":
    main()
