# -*- coding: utf-8 -*-
# Portainer /endpoints endpoint.

from __future__ import annotations

from urllib.parse import urlencode


def list_endpoints(client):
    return client.request("GET", "/endpoints") or []


def find_endpoint(client, name):
    for endpoint in list_endpoints(client):
        if endpoint.get("Name") == name:
            return endpoint
    return None


def create_endpoint(client, name, fields):
    body = urlencode(dict({"Name": name}, **fields))
    return client.request(
        "POST",
        "/endpoints",
        headers={"Content-Type": "application/x-www-form-urlencoded"},
        data=body,
    )


def delete_endpoint(client, endpoint_id):
    client.request("DELETE", "/endpoints/%s" % endpoint_id, ok_statuses=(200, 204))
