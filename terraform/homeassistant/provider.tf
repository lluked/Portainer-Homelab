provider "portainer" {
  # A trailing "/api" (as used by the Ansible role's portainer_api_url) is
  # stripped so this works whether or not the caller includes it - the
  # provider appends its own.
  endpoint = trimsuffix(var.portainer_api_url, "/api")

  api_user     = var.portainer_username
  api_password = var.portainer_password

  skip_ssl_verify = !var.portainer_api_validate_certs
}
