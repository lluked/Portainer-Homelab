# Shared by every stack's provider.tf (module "vault_env" { source =
# "../modules/vault_env" }) so vault/vault.env - VAULT_ADDR and
# VAULT_KEYS_FILE, the single source of truth also read by
# vault/vault-local.sh and group_vars/remote_host/hashi_vault.yml
# (see ../../../README.md's "Secrets" section) - is only parsed in one
# place instead of once per stack.
#
# try(): both fall back to this repo's documented local-Vault defaults
# when vault/vault.env doesn't exist yet, or a key is missing from it.
#
# address_override/token_override exist for callers outside this repo's
# own working tree - e.g. another repo's stack sourcing this module via a
# git:// source, where path.module resolves inside Terraform's own clone
# of this repo rather than the caller's actual checkout, so the file()
# lookups below would silently read (or fail to find) the wrong repo_root
# entirely. Passing both explicitly (e.g. from that repo's own
# TF_VAR_vault_address/TF_VAR_vault_token, sourced from this repo's
# vault/vault.env and vault/vault_keys.json by hand) skips the file
# lookups altogether. Left null (the default) for every stack in this
# repo, which keeps using the file-based lookup as before.

variable "address_override" {
  type    = string
  default = null
}

variable "token_override" {
  type      = string
  default   = null
  sensitive = true
}

locals {
  repo_root       = "${path.module}/../../.."
  env_content     = try(file("${local.repo_root}/vault/vault.env"), "")
  vault_addr      = try(regex("(?m)^VAULT_ADDR=(.*)$", local.env_content)[0], "http://127.0.0.1:8200")
  # VAULT_KEYS_FILE is relative to vault/ (the convention shared with
  # vault/vault-local.sh and Ansible's hashi_vault.yml).
  vault_keys_file = try(regex("(?m)^VAULT_KEYS_FILE=(.*)$", local.env_content)[0], "vault_keys.json")
}

output "address" {
  value = var.address_override != null ? var.address_override : local.vault_addr
}

output "token" {
  # Falls back to an empty token when vault/vault_keys.json doesn't exist
  # yet, or isn't needed at all because the calling stack's
  # portainer_username/portainer_password are both set explicitly. Kept as
  # a ternary rather than coalesce() - coalesce() errors out when every
  # argument is null/"", which that empty-string fallback deliberately
  # allows.
  value     = var.token_override != null ? var.token_override : try(jsondecode(file("${local.repo_root}/vault/${local.vault_keys_file}")).root_token, "")
  sensitive = true
}
