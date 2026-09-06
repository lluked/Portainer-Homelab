provider "portainer" {
  # A trailing "/api" (as used by the Ansible role's portainer_api_url) is
  # stripped so this works whether or not the caller includes it - the
  # provider appends its own.
  endpoint = trimsuffix(var.portainer_api_url, "/api")

  api_user     = coalesce(var.portainer_username, try(data.vault_kv_secret_v2.portainer[0].data["username"], null))
  api_password = coalesce(var.portainer_password, try(data.vault_kv_secret_v2.portainer[0].data["password"], null))

  skip_ssl_verify = !var.portainer_api_validate_certs
}

# Points at the local Vault setup directly (see ../../../README.md's
# "Secrets" section and ../../modules/vault_env/main.tf) - no VAULT_ADDR/VAULT_TOKEN
# env vars needed; reads vault/vault.env and vault/vault_keys.json.
# skip_child_token: skips minting a short-lived child token per run -
# unnecessary since the root token is already this machine's own local
# secret.
module "vault_env" {
  source = "../../modules/vault_env"
}

provider "vault" {
  address          = module.vault_env.address
  token            = module.vault_env.token
  skip_child_token = true
}

# Only read when portainer_username/portainer_password aren't both set
# explicitly, so Vault doesn't need to be reachable at all for a run that
# passes both directly.
data "vault_kv_secret_v2" "portainer" {
  count = (var.portainer_username == null || var.portainer_password == null) ? 1 : 0
  mount = "secret"
  name  = "portainer"
}
