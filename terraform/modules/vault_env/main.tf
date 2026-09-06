# Shared by every stack's provider.tf (module "vault_env" { source =
# "../modules/vault_env" }) so vault/vault.env - VAULT_ADDR and
# VAULT_KEYS_FILE, the single source of truth also read by
# vault/vault-local.sh and group_vars/remote_host/hashi_vault.yml
# (see ../../../README.md's "Secrets" section) - is only parsed in one
# place instead of once per stack.
#
# try(): both fall back to this repo's documented local-Vault defaults
# when vault/vault.env doesn't exist yet, or a key is missing from it.

locals {
  repo_root       = "${path.module}/../../.."
  env_content     = try(file("${local.repo_root}/vault/vault.env"), "")
  vault_addr      = try(regex("(?m)^VAULT_ADDR=(.*)$", local.env_content)[0], "http://127.0.0.1:8200")
  # VAULT_KEYS_FILE is relative to vault/ (the convention shared with
  # vault/vault-local.sh and Ansible's hashi_vault.yml).
  vault_keys_file = try(regex("(?m)^VAULT_KEYS_FILE=(.*)$", local.env_content)[0], "vault_keys.json")
}

output "address" {
  value = local.vault_addr
}

output "token" {
  # Falls back to an empty token when vault/vault_keys.json doesn't exist
  # yet, or isn't needed at all because the calling stack's
  # portainer_username/portainer_password are both set explicitly.
  value     = try(jsondecode(file("${local.repo_root}/vault/${local.vault_keys_file}")).root_token, "")
  sensitive = true
}
