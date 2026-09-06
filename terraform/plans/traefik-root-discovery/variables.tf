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
  description = "Base domain stacks' Traefik router rules are served under. Unused by this stack's Compose file (traefik-root-discovery has no Traefik labels) - kept for consistency with the other stacks, since playbooks/portainer_stacks.yml passes it to all of them."
  type        = string
  default     = null
}

variable "portainer_api_validate_certs" {
  description = "Whether to validate the Portainer API's TLS certificate."
  type        = bool
  default     = false
}

variable "endpoint_name" {
  description = "Name of the Portainer environment (endpoint) to deploy into. Must be the root (rootful) environment - socket-proxy needs to bind-mount the real root /var/run/docker.sock, which a rootless environment can't reach."
  type        = string
  default     = "root"
}

variable "install_dir" {
  description = "Directory on the host for this stack's data, e.g. /opt/traefik-root-discovery."
  type        = string
  default     = "/opt/traefik-root-discovery"
}

variable "volume_mounts" {
  description = "Bind-mount source subdirectories this stack needs, relative to install_dir, keyed by name. install_dir/<value> must exist before the stack is deployed - the Ansible role reads this variable's resolved value (via `terraform show -json` on a plan), together with install_dir, to pre-create them on the host before applying. dynamic_dir is where traefik-root-discovery writes the Traefik dynamic (file provider) config it derives from root containers' traefik.* labels - plans/traefik/ bind-mounts this same host path read-only (see its root_dynamic_config_dir variable), which is why this stack must be applied before plans/traefik/ (see ../../../playbooks/portainer_stacks.yml's stack order)."
  type        = map(string)
  default = {
    dynamic_dir = "dynamic"
  }
}

variable "ssh_host" {
  description = "Host to SSH into to create install_dir and volume_mounts subdirectories - the actual Docker host, since that's where these bind-mount source paths must exist. Terraform itself doesn't need to run there; this is only used by the install_dirs provisioner's connection. Also passed to traefik-root-discovery as the address it advertises for root containers' published ports, since that's the only address reachable from the separate rootless daemon Traefik itself runs on."
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
