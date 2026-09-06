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
  description = "Base domain this stack's Traefik router rule is served under (adguardhome.<lab_domain>). Optional - if unset (the default), read from secret/lab in Vault instead (see main.tf); Vault isn't contacted at all if this is set explicitly."
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
  default     = "root"
}

variable "install_dir" {
  description = "Directory on the host for this stack's data, e.g. /opt/adguardhome."
  type        = string
  default     = "/opt/adguardhome"
}

variable "volume_mounts" {
  description = "Bind-mount source subdirectories this stack needs, relative to install_dir, keyed by name (adguardhome_work_dir, adguardhome_conf_dir). install_dir/<value> must exist before the stack is deployed - the Ansible role reads this variable's resolved value (via `terraform show -json` on a plan), together with install_dir, to pre-create them on the host before applying."
  type        = map(string)
  default = {
    adguardhome_work_dir = "work"
    adguardhome_conf_dir = "conf"
  }
}

variable "docker_managed_volumes" {
  description = "If false, bind-mount install_dir/volume_mounts subdirectories on the host (pre-created via SSH by install_dirs) into the containers. If true, skip host directory creation and use plain Docker-managed named volumes instead - install_dir and volume_mounts are then unused."
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
