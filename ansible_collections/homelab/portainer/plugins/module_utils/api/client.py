# -*- coding: utf-8 -*-

from __future__ import annotations

import json

from ansible.module_utils.urls import fetch_url


class PortainerAPIError(Exception):
    def __init__(self, message, status=None, body=None):
        super().__init__(message)
        self.status = status
        self.body = body


class PortainerClient:
    """Shared HTTP transport for the Portainer API.

    Construct with headers={"X-API-Key": ...} for API-key auth, or leave headers
    unset and call login() to authenticate with a username/password instead.
    """

    def __init__(self, module, api_url, headers=None):
        self.module = module
        self.api_url = api_url.rstrip("/")
        self.headers = dict(headers) if headers else {"Content-Type": "application/json"}

    def raw_request(self, method, path, headers=None, data=None, body=None, ok_statuses=(200,)):
        url = self.api_url + path
        req_headers = dict(self.headers)
        if headers:
            req_headers.update(headers)
        if data is None and body is not None:
            data = json.dumps(body)

        resp, info = fetch_url(self.module, url, method=method, data=data, headers=req_headers)
        status = info.get("status", -1)

        # fetch_url has already consumed resp on some error responses (status >= 400) -
        # the body it read is in info["body"] instead, with resp.read() coming back empty.
        raw = resp.read() if resp is not None else None
        if not raw:
            raw = info.get("body")
        text = raw.decode("utf-8") if isinstance(raw, bytes) else (raw or "")

        if status not in ok_statuses:
            raise PortainerAPIError(
                "Portainer API request failed: %s %s -> %s" % (method, path, status),
                status=status,
                body=text,
            )
        return status, text

    def request(self, method, path, headers=None, data=None, body=None, ok_statuses=(200,)):
        _, text = self.raw_request(method, path, headers=headers, data=data, body=body, ok_statuses=ok_statuses)
        if not text:
            return None
        try:
            return json.loads(text)
        except ValueError:
            return text

    def login(self, username, password):
        result = self.request("POST", "/auth", body={"Username": username, "Password": password})
        self.headers["Authorization"] = "Bearer %s" % result["jwt"]
