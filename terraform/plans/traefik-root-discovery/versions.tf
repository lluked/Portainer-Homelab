terraform {
  required_version = ">= 1.5"

  required_providers {
    portainer = {
      # Locally-built patch of portainer/portainer 1.35.0: the upstream
      # create path for portainer_stack deploys the stack, then
      # immediately sends a follow-up PUT to apply prune/webhook
      # settings. Against this Portainer install (2.45.0), that follow-up
      # call routinely 409s with "Stack deployment is already in
      # progress" because the server hasn't cleared its internal
      # per-stack deployment lock yet, even though the deploy itself
      # succeeded - so `apply` was tainting and redeploying a perfectly
      # working stack every run. This build (source cloned from
      # github.com/portainer/terraform-provider-portainer @ 1.35.0, patch
      # in internal/resource_stack.go) retries that PUT with a 5s backoff
      # (up to 12 attempts) instead of failing outright. Installed under
      # ~/.terraform.d/plugins/localdomain/local/portainer/1.35.0-patch1/.
      # Not a substitute for an upstream fix - revert to
      # source = "portainer/portainer" once this is fixed there.
      source  = "localdomain/local/portainer"
      version = "1.35.0-patch1"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "~> 4.0"
    }
  }
}
