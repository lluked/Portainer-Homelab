# Creates install_dir and each volume_mounts subdirectory under it on
# ssh_host (the actual Docker host) - not necessarily the host running
# `terraform apply` itself, since this is normally invoked remotely (from
# wherever `ansible-playbook` runs) rather than on that host.
# Connects over SSH and uses sudo there, mirroring the Ansible role's own
# become: true this replaced. Only re-runs if install_dir/volume_mounts
# themselves change; it won't recreate a directory later removed by hand.
resource "null_resource" "install_dirs" {
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

resource "portainer_stack" "homeassistant" {
  name            = "homeassistant"
  deployment_type = "standalone"
  method          = "string"
  endpoint_id     = data.portainer_environment.target.id
  prune           = true
  depends_on      = [null_resource.install_dirs]

  stack_file_content = templatefile(
    "${path.module}/docker-compose.yml.tftpl",
    {
      homeassistant_config_dir = "${var.install_dir}/${var.volume_mounts["homeassistant_config_dir"]}"
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
