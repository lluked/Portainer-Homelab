# -*- coding: utf-8 -*-
# Portainer /users endpoint, including the /users/{id}/tokens and /users/admin/init
# sub-resources.

from __future__ import annotations

from ansible_collections.homelab.portainer.plugins.module_utils.api.client import PortainerAPIError


def init_admin(client, username, password, setup_token):
    # Create-only and one-time - Portainer rejects every call after the first admin account
    # exists, so there's nothing to read/update/delete here.
    headers = {}
    if setup_token:
        headers["X-Setup-Token"] = setup_token

    status, _ = client.raw_request(
        "POST",
        "/users/admin/init",
        body={"Username": username, "Password": password},
        headers=headers,
        ok_statuses=(200, 409),
    )
    return status


def list_users(client):
    return client.request("GET", "/users") or []


def find_user_id(client, username):
    for user in list_users(client):
        if user.get("Username") == username:
            return user["Id"]
    raise PortainerAPIError("No Portainer user found with username %s" % username)


def list_tokens(client, user_id):
    return client.request("GET", "/users/%s/tokens" % user_id) or []


def find_token(client, user_id, description):
    for token in list_tokens(client, user_id):
        if token.get("Description") == description:
            return token
    return None


def create_token(client, user_id, description, password):
    return client.request(
        "POST",
        "/users/%s/tokens" % user_id,
        body={"description": description, "password": password},
    )


def delete_token(client, user_id, token_id):
    # Portainer's API has no update for tokens - they're immutable once created (delete and
    # recreate is the only way to change one).
    client.request("DELETE", "/users/%s/tokens/%s" % (user_id, token_id), ok_statuses=(200, 204))
