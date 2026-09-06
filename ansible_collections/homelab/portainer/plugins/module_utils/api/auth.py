# -*- coding: utf-8 -*-
# Portainer /auth endpoint. Login-only - Portainer exposes no read/update/delete here (JWTs
# are stateless, so there's no session resource to manage beyond issuing one).

from __future__ import annotations

from ansible_collections.homelab.portainer.plugins.module_utils.api.client import PortainerAPIError


def credentials_are_valid(client, username, password):
    try:
        client.login(username, password)
        return True
    except PortainerAPIError:
        return False
