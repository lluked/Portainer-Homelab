# -*- coding: utf-8 -*-
# Portainer /endpoint_groups endpoint.

from __future__ import annotations


def list_groups(client):
    return client.request("GET", "/endpoint_groups") or []


def find_group(client, name):
    for group in list_groups(client):
        if group.get("Name") == name:
            return group
    return None


def create_group(client, name):
    return client.request("POST", "/endpoint_groups", body={"Name": name})
