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

# Observed against Portainer 2.45.0 (not a filed/tracked issue upstream,
# just reproduced locally while debugging this): portainer_stack's create path
# deploys the compose stack, then immediately issues a follow-up PUT to
# apply prune/webhook settings. Portainer's server hasn't always cleared
# its internal per-stack deployment lock by the time that follow-up
# lands, so it 409s ("Stack deployment is already in progress") even
# though the underlying stack deployed fine. Confirmed independent of
# provider version (reproduces on both 1.35.0 and 1.34.3) - it's a
# server-side race, not a provider regression. If `apply` fails this way,
# check `docker ps` / the Portainer UI: the stack is almost always
# actually up. Run `terraform untaint portainer_stack.adguardhome` to
# clear the false failure instead of re-applying (which just destroys the
# working stack and re-triggers the same race on recreate).
resource "portainer_stack" "adguardhome" {
  name            = "adguardhome"
  deployment_type = "standalone"
  method          = "string"
  endpoint_id     = data.portainer_environment.target.id
  prune           = true
  depends_on      = [null_resource.install_dirs]

  stack_file_content = templatefile(
    "${path.module}/docker-compose.yml.tftpl",
    {
      adguardhome_work_dir = "${var.install_dir}/${var.volume_mounts["adguardhome_work_dir"]}"
      adguardhome_conf_dir = "${var.install_dir}/${var.volume_mounts["adguardhome_conf_dir"]}"
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
