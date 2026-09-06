# Creates install_dir and each volume_mounts subdirectory under it on
# ssh_host (the actual Docker host) - not necessarily the host running
# `terraform apply` itself, since this is normally invoked remotely (from
# wherever `ansible-playbook` runs) rather than on that host.
# Connects over SSH and uses sudo there, mirroring the Ansible role's own
# become: true this replaced. Only re-runs if install_dir/volume_mounts
# themselves change; it won't recreate a directory later removed by hand.
resource "null_resource" "install_dirs" {
  count = var.docker_managed_volumes ? 0 : 1

  triggers = {
    install_dir   = var.install_dir
    volume_mounts = jsonencode(var.volume_mounts)
  }

  connection {
    type        = "ssh"
    host        = var.ssh_host
    user        = var.ssh_user
    private_key = file(pathexpand(var.ssh_private_key_file))
  }

  provisioner "remote-exec" {
    inline = concat(
      [
        "sudo mkdir -p ${var.install_dir}",
        "sudo chown \"$(id -u):$(id -g)\" ${var.install_dir}",
      ],
      flatten([
        for subpath in values(var.volume_mounts) : [
          "sudo mkdir -p ${var.install_dir}/${subpath}",
          "sudo chown \"$(id -u):$(id -g)\" ${var.install_dir}/${subpath}",
        ]
      ])
    )
  }
}

data "portainer_environment" "target" {
  name = var.endpoint_name
}

# Only read when lab_domain isn't set explicitly, so Vault doesn't need to
# be reachable at all for a run that passes it directly - same pattern as
# provider.tf's data.vault_kv_secret_v2.portainer.
data "vault_kv_secret_v2" "lab" {
  count = var.lab_domain == null ? 1 : 0
  mount = "secret"
  name  = "lab"
}

locals {
  lab_domain = coalesce(var.lab_domain, try(data.vault_kv_secret_v2.lab[0].data["domain"], null))
}

resource "portainer_stack" "traefik" {
  name            = "traefik"
  deployment_type = "standalone"
  method          = "string"
  endpoint_id     = data.portainer_environment.target.id
  prune           = true
  depends_on      = [null_resource.install_dirs]

  stack_file_content = templatefile(
    "${path.module}/docker-compose.yml.tftpl",
    {
      lab_domain = local.lab_domain
    }
  )

  dynamic "env" {
    for_each = var.env
    content {
      name  = env.key
      value = env.value
    }
  }
}
