#!/usr/bin/env bash
# Starts/stops the local Vault server used as this repo's secrets backend
# (see README.md's "Secrets" section). Runs only on this machine - never on
# remote_host (the Pi). `start` also auto-unseals using the keys saved in
# vault/vault_keys.json during the one-time `vault operator init` (see
# README.md); it does nothing to secret data itself and never creates
# vault/vault_keys.json - that's a one-time manual step.

set -euo pipefail

# vault/ is this script's own directory - cd there so the relative paths
# below (vault.env, config.hcl, etc.) work regardless of where this
# script is invoked from.
VAULT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$VAULT_DIR"

# vault.env (VAULT_ADDR, VAULT_KEYS_FILE) is the single source of truth
# also read by group_vars/remote_host/hashi_vault.yml and every
# terraform/*/provider.tf (via terraform/vault_env/main.tf) - it's a real
# shell env file, so this script just sources it directly.
if [[ -f vault.env ]]; then
  set -a
  source vault.env
  set +a
fi

pid_file="vault.pid"
log_file="vault.log"
# VAULT_KEYS_FILE (from vault.env) is relative to vault/ (the convention
# shared with Terraform/Ansible) - already this script's own cwd, so no
# extra path segment needed here.
keys_file="$VAULT_KEYS_FILE"

start() {
  if [[ -f "$pid_file" ]] && kill -0 "$(cat "$pid_file")" 2>/dev/null; then
    echo "vault-local: already running (pid $(cat "$pid_file"))"
  else
    # config.hcl is generated (git-ignored) rather than committed, so
    # VAULT_ADDR has exactly one source of truth (vault.env) instead of
    # being duplicated by hand into the listener's bind address too.
    listen_addr="${VAULT_ADDR#http://}"
    listen_addr="${listen_addr#https://}"
    sed "s|__VAULT_LISTEN_ADDR__|$listen_addr|" config.hcl.tmpl >config.hcl

    echo "vault-local: starting vault server..."
    nohup vault server -config=config.hcl >"$log_file" 2>&1 &
    echo $! >"$pid_file"
    for _ in $(seq 1 30); do
      # `vault status` exits 1 when the server is unreachable (still
      # starting), but 0 (unsealed) or 2 (sealed) once it's actually up -
      # either of those means it's time to stop waiting.
      set +e
      vault status >/dev/null 2>&1
      reachable=$?
      set -e
      [[ "$reachable" -ne 1 ]] && break
      sleep 1
    done
  fi

  # Captured once into a variable rather than re-piping "vault status"
  # into grep each time: with `pipefail` (set above), a pipeline's exit
  # status is non-zero whenever vault itself exits non-zero - which it
  # legitimately does for a sealed/uninitialized server - even if grep
  # found its match, silently short-circuiting these checks.
  set +e
  status_json="$(vault status -format=json 2>/dev/null)"
  set -e

  if echo "$status_json" | jq -e '.initialized == false' >/dev/null 2>&1; then
    cat <<'EOF'
vault-local: not yet initialized. Run once:
  vault operator init -key-shares=3 -key-threshold=2
then save the unseal keys + initial root token into vault/vault_keys.json
(chmod 600) - see README.md's "Secrets" section for the exact format and
the rest of the one-time setup (enabling kv-v2 and seeding secret values).
EOF
    return 0
  fi

  if echo "$status_json" | jq -e '.sealed == true' >/dev/null 2>&1; then
    if [[ ! -f "$keys_file" ]]; then
      echo "vault-local: sealed, but $keys_file is missing - unseal manually with 'vault operator unseal'." >&2
      return 1
    fi
    echo "vault-local: unsealing..."
    jq -r '.unseal_keys_b64[]' "$keys_file" | while read -r key; do
      vault operator unseal "$key" >/dev/null
    done
  fi

  echo "vault-local: $(vault status -format=json | jq -r 'if .sealed then "still sealed" else "unsealed and ready" end')"
}

stop() {
  if [[ -f "$pid_file" ]] && kill -0 "$(cat "$pid_file")" 2>/dev/null; then
    kill "$(cat "$pid_file")"
    rm -f "$pid_file"
    echo "vault-local: stopped"
  else
    echo "vault-local: not running"
  fi
}

case "${1:-}" in
  start) start ;;
  stop) stop ;;
  *)
    echo "usage: $0 {start|stop}" >&2
    exit 1
    ;;
esac
