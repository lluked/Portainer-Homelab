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

# Home Assistant's Bluetooth integration talks to BlueZ over the host's
# D-Bus system bus (bind-mounted in by docker-compose.yml.tftpl), which
# Docker's default AppArmor profile denies outright - it ships with no
# `dbus` rules at all, and D-Bus mediation is default-deny once a profile
# is confined. This loads a profile that's Docker's default profile plus
# exactly the D-Bus permissions needed to reach BlueZ (see
# apparmor/docker-homeassistant), referenced by the compose file's
# `security_opt: apparmor=docker-homeassistant` instead of the default.
resource "null_resource" "apparmor_profile" {
  triggers = {
    profile = filesha256("${path.module}/apparmor/docker-homeassistant")
  }

  connection {
    type        = "ssh"
    host        = var.ssh_host
    user        = var.ssh_user
    private_key = file(pathexpand(var.ssh_private_key_file))
  }

  provisioner "file" {
    source      = "${path.module}/apparmor/docker-homeassistant"
    destination = "/tmp/docker-homeassistant.apparmor"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo mv /tmp/docker-homeassistant.apparmor /etc/apparmor.d/docker-homeassistant",
      "sudo apparmor_parser -r /etc/apparmor.d/docker-homeassistant",
    ]
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

resource "portainer_stack" "homeassistant" {
  name            = "homeassistant"
  deployment_type = "standalone"
  method          = "string"
  endpoint_id     = data.portainer_environment.target.id
  prune           = true
  depends_on      = [null_resource.install_dirs, null_resource.apparmor_profile]

  stack_file_content = templatefile(
    "${path.module}/docker-compose.yml.tftpl",
    {
      docker_managed_volumes   = var.docker_managed_volumes
      homeassistant_config_dir = "${var.install_dir}/${var.volume_mounts["homeassistant_config_dir"]}"
      lab_domain               = local.lab_domain
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
