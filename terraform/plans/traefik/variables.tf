variable "portainer_api_url" {
  description = "Base URL of the Portainer API."
  type        = string
  default     = "https://192.168.1.10:9443/api"
}

variable "portainer_username" {
  description = "Portainer username used to authenticate. Optional - if unset (the default), read from secret/portainer in Vault instead (see provider.tf); Vault isn't contacted at all if this is set explicitly."
  type        = string
  default     = null
}

variable "portainer_password" {
  description = "Portainer password used to authenticate. Optional - if unset (the default), read from secret/portainer in Vault instead (see provider.tf); Vault isn't contacted at all if this is set explicitly."
  type        = string
  default     = null
  sensitive   = true
}

variable "lab_domain" {
  description = "Base domain the stack's Traefik router rule is served under (traefik.<lab_domain>). Optional - if unset (the default), read from secret/lab in Vault instead (see main.tf); Vault isn't contacted at all if this is set explicitly."
  type        = string
  default     = null
}

variable "portainer_api_validate_certs" {
  description = "Whether to validate the Portainer API's TLS certificate."
  type        = bool
  default     = false
}

variable "endpoint_name" {
  description = "Name of the Portainer environment (endpoint) to deploy into."
  type        = string
  default     = "rootless"
}

variable "install_dir" {
  description = "Directory on the host for this stack's data, e.g. /opt/traefik. Unused by this stack's Compose file (traefik has no bind mounts under it) - kept for consistency with the other stacks."
  type        = string
  default     = "/opt/traefik"
}

variable "volume_mounts" {
  description = "Bind-mount source subdirectories this stack needs, relative to install_dir, keyed by name. Unused by this stack's Compose file (traefik has no bind mounts under it) - kept for consistency with the other stacks. The Ansible role reads this variable's resolved value (via `terraform show -json` on a plan), together with install_dir, to pre-create these directories on the host before applying."
  type        = map(string)
  default     = {}
}

variable "docker_managed_volumes" {
  description = "If false, create install_dir/volume_mounts subdirectories on the host via SSH before deploying. Unused by this stack's Compose file (traefik has no bind mounts under it) - kept for consistency with the other stacks."
  type        = bool
  default     = false
}

variable "ssh_host" {
  description = "Host to SSH into to create install_dir and volume_mounts subdirectories - the actual Docker host, since that's where these bind-mount source paths must exist. Terraform itself doesn't need to run there; this is only used by the install_dirs provisioner's connection."
  type        = string
  default     = "192.168.1.10"
}

variable "ssh_user" {
  description = "SSH username for ssh_host."
  type        = string
  default     = "admin"
}

variable "ssh_private_key_file" {
  description = "Path to the SSH private key for ssh_user@ssh_host. A leading \"~\" is expanded to the home directory."
  type        = string
}

variable "env" {
  description = "Environment variables passed to the stack (name -> value)."
  type        = map(string)
  default     = {}
  sensitive   = true
}

variable "root_dynamic_config_dir" {
  description = "Host path bind-mounted read-only as Traefik's file provider directory - kept up to date by ../traefik-root-discovery/, which derives it from traefik.* labels on containers running on the root (rootful) Docker daemon. Traefik's own Docker provider (below) only ever sees the rootless daemon it shares with this container, since a rootless container can't bind-mount the root socket directly - this file provider is how labels from the root side reach Traefik at all. Must match ../traefik-root-discovery/'s install_dir/volume_mounts (install_dir + volume_mounts[\"dynamic_dir\"]). This stack's own null_resource.root_dynamic_config_dir (main.tf) creates this path on ssh_host before Traefik starts, so - unlike before - it no longer matters whether ../traefik-root-discovery/ has been applied yet; that stack creates and chowns the same path the same way, so either apply order works."
  type        = string
  default     = "/opt/traefik-root-discovery/dynamic"
}
