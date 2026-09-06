#!/usr/bin/env bash
# One-time (and re-runnable) setup:
#   1. Creates inventory.ini if it doesn't exist yet - prompting for
#      host/user/key, defaulting each to inventory.ini.example's values -
#      then generates a plan.auto.tfvars in every terraform/plans/<stack>/
#      directory from it: portainer_api_url/ssh_host/ssh_user/
#      ssh_private_key_file. Terraform loads *.auto.tfvars automatically
#      (no -var-file needed), so every plan gets these without
#      hand-copying terraform.tfvars.example into each one, and stays in
#      sync with a single inventory.ini entry instead of duplicating
#      host/user/key by hand per-stack.
#   2. Sets up the local Vault secrets backend if it isn't already:
#      starts it (vault/vault-local.sh, which also generates
#      vault/config.hcl), initializes it if needed (saving
#      vault/vault_keys.json), enables the kv-v2 engine, and seeds
#      secret/portainer if it's empty (prompts for username/password,
#      defaulting to admin/a random password if left blank).
#
# Safe to re-run any time - each step only does something if it hasn't
# been done yet.

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$repo_root"

# Parses the first non-empty line under [remote_host] in the given file:
#   <host> ansible_user=<user> ansible_ssh_private_key_file=<key>
# Prints host, user and key each on their own line.
parse_remote_host() {
  local line
  line="$(awk '/^\[remote_host\]/{f=1;next} f && NF{print; exit}' "$1")"
  awk '{print $1}' <<<"$line"
  grep -oE 'ansible_user=[^ ]+' <<<"$line" | cut -d= -f2
  grep -oE 'ansible_ssh_private_key_file=[^ ]+' <<<"$line" | cut -d= -f2
}

if [[ -f inventory.ini ]]; then
  IFS=$'\n' read -r -d '' host user key < <(parse_remote_host inventory.ini && printf '\0')
else
  IFS=$'\n' read -r -d '' default_host default_user default_key < <(parse_remote_host inventory.ini.example && printf '\0')

  read -r -p "setup: remote host address [$default_host]: " host
  host="${host:-$default_host}"
  read -r -p "setup: SSH user [$default_user]: " user
  user="${user:-$default_user}"
  read -r -p "setup: SSH private key file [$default_key]: " key
  key="${key:-$default_key}"

  printf '[remote_host]\n%s ansible_user=%s ansible_ssh_private_key_file=%s\n' \
    "$host" "$user" "$key" >inventory.ini
  echo "setup: wrote inventory.ini"
fi

if [[ -z "$host" || -z "$user" || -z "$key" ]]; then
  echo "setup: couldn't parse host/user/key from inventory.ini's [remote_host] entry - check its format against inventory.ini.example." >&2
  exit 1
fi

for plan_dir in terraform/plans/*/; do
  cat >"${plan_dir}plan.auto.tfvars" <<EOF
portainer_api_url    = "https://${host}:9443/api"
ssh_host             = "${host}"
ssh_user             = "${user}"
ssh_private_key_file = "${key}"
EOF
  echo "setup: wrote ${plan_dir}plan.auto.tfvars"
done

# --- Vault ---

if ! command -v vault >/dev/null 2>&1; then
  cat <<'EOF'
setup: `vault` isn't installed - install it, then re-run this script:
  brew tap hashicorp/tap
  brew install hashicorp/tap/vault
EOF
  exit 1
fi

./vault/vault-local.sh start

# vault/vault.env (VAULT_ADDR, VAULT_KEYS_FILE) is the single source of
# truth - sourced here directly rather than inherited from
# vault-local.sh above, since a child process's exports never propagate
# back to this shell.
set -a
source vault/vault.env
set +a
keys_path="vault/$VAULT_KEYS_FILE"

if [[ ! -f "$keys_path" ]]; then
  echo "setup: initializing Vault (one-time - saving unseal keys/root token to $keys_path)..."
  vault operator init -key-shares=3 -key-threshold=2 -format=json >"$keys_path"
  chmod 600 "$keys_path"
  # Now that the keys file exists, this unseals using it.
  ./vault/vault-local.sh start
fi

export VAULT_TOKEN="$(jq -r '.root_token' "$keys_path")"

if ! vault secrets list -format=json | jq -e 'has("secret/")' >/dev/null 2>&1; then
  echo "setup: enabling the kv-v2 secrets engine at secret/..."
  vault secrets enable -path=secret kv-v2
fi

if vault kv get secret/portainer >/dev/null 2>&1; then
  read -r -p "setup: secret/portainer already exists - update it? [y/N]: " portainer_update
  if [[ "$portainer_update" =~ ^[Yy] ]]; then
    current_username="$(vault kv get -field=username secret/portainer)"
    current_password="$(vault kv get -field=password secret/portainer)"

    read -r -p "setup: Portainer admin username (blank to keep current): " portainer_username
    portainer_username="${portainer_username:-$current_username}"
    read -r -s -p "setup: Portainer admin password (blank to keep current): " portainer_password
    echo
    portainer_password="${portainer_password:-$current_password}"

    vault kv put secret/portainer username="$portainer_username" password="$portainer_password"
    unset current_username current_password portainer_username portainer_password
  fi
  unset portainer_update
else
  read -r -p "setup: Portainer admin username for secret/portainer (blank for admin): " portainer_username
  portainer_username="${portainer_username:-admin}"
  read -r -s -p "setup: Portainer admin password for secret/portainer (blank to generate one): " portainer_password
  echo
  if [[ -z "$portainer_password" ]]; then
    portainer_password="$(openssl rand -base64 24)"
    echo "setup: generated a random password."
  fi
  vault kv put secret/portainer username="$portainer_username" password="$portainer_password"
  unset portainer_username portainer_password
fi

echo "setup: done."
