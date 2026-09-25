# Goal 1. Both services running, java-gateway reachable on its own public HTTPS ingress, 
# python-validator reachable only from inside the Container Apps environment — 
# the direct analogue of the existing "port 8081 public, port 8082 internal-only" security-group rule,
# expressed here as ingress scope rather than a security-group CIDR.

# Goal 2. python-validator reads DATABASE_URL and API_SECURITY_TOKEN from Key Vault at start-up
# through its own managed identity — no secret embedded in the Container App definition, 
# no secret in Terraform state beyond the random_password resources already there.
# This is the stage that stands in for AKS workload identity.

# How this differs from AKS workload identity: On AKS, the same outcome needs:
# a federated identity credential whose subject matches system:serviceaccount:<namespace>:<name> exactly, 
# a Kubernetes ServiceAccount annotated with the managed identity's client ID, 
# the AKS OIDC issuer URL retrieved and registered on the federated credential, 
# and the Secrets Store CSI driver add-on mounting the secret as a file or environment variable.
# On Container Apps, the identity is simply attached to the app already donethe  identity block;
# Azure resolves "which container is asking" without any Kubernetes-shaped intermediary.
# The Entra-ID-to-Key-Vault part of the setup — a workload authenticating as itself, not as a stored secret —
# is identical in both; only the container-platform-specific plumbing to reach that point differs,
# and Container Apps has less of it.

resource "azurerm_container_app" "python_validator" {
  name                         = "poc-eai-python-validator"
  container_app_environment_id = azurerm_container_app_environment.poc.id
  resource_group_name          = azurerm_resource_group.poc_aca.name
  revision_mode                = "Single"
  workload_profile_name        = "Consumption" # matches the environment's own workload_profile
                                                 # declaring it explicitly else terraform tries to
                                                 # remove it on every plan/apply, even though Azure keeps it there anyway

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.aca.id]
  }

  registry {
    server   = data.azurerm_container_registry.shared.login_server
    identity = azurerm_user_assigned_identity.aca.id   # pulls using the managed identity, no admin credential
  }

  ingress {
    external_enabled = false   # internal-only: same intent as port 8082 never being opened in the VM path
    target_port       = 8082
    traffic_weight {
        percentage = 100
        latest_revision = true
    }
  }

  # These two secret blocks below are added later, along with the 
  # "DATABASE_URL" and "API_SECURITY_TOKEN" env vars addition to the 
  # python-validator container above,
  # once the Key Vault secret references exist — deliberately staged 
  # so the container's first deploy is verifiable without them.
  secret {
    name                = "database-url"
    key_vault_secret_id = "${azurerm_key_vault.poc.vault_uri}secrets/${azurerm_key_vault_secret.db_password.name}"
    identity             = azurerm_user_assigned_identity.aca.id
  }

  secret {
    name                = "api-security-token"
    key_vault_secret_id = azurerm_key_vault_secret.api_token.id
    identity             = azurerm_user_assigned_identity.aca.id
  }

  template {
    container {
      name   = "python-validator"
      # image  = "${data.azurerm_container_registry.shared.login_server}/eai-python-validator:<SHA>"
      # The SHA tag is the same SHA the VM path already built and pushed to the shared registry - 8231a... string below.
      image  = "${data.azurerm_container_registry.shared.login_server}/eai-python-validator:8231a19d3b6ae1e085a678a02f7da77b4681e39b"
      cpu    = 0.5
      memory = "1Gi"
      env {
        name  = "TZ"
        value = "Asia/Kolkata"
      }
      # These DATABASE_URL and API_SECURITY_TOKEN blocks below are added later, 
      # once the Key Vault secret references exist — deliberately staged 
      # so the container's first deploy is verifiable without them.
      env {
        name        = "DATABASE_URL"
        secret_name = "database-url"
      }
      env {
        name        = "API_SECURITY_TOKEN"
        secret_name = "api-security-token"
      }      
    }
    min_replicas = 0   # scales to zero when idle — the Consumption-plan trade-off
    max_replicas = 1
  }
}

resource "azurerm_container_app" "java_gateway" {
  name                         = "poc-eai-java-gateway"
  container_app_environment_id = azurerm_container_app_environment.poc.id
  resource_group_name          = azurerm_resource_group.poc_aca.name
  revision_mode                = "Single"
  workload_profile_name        = "Consumption" # matches the environment's own workload_profile
                                                 # declaring it explicitly else terraform tries to
                                                 # remove it on every plan/apply, even though Azure keeps it there anyway

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.aca.id]
  }

  registry {
    server   = data.azurerm_container_registry.shared.login_server
    identity = azurerm_user_assigned_identity.aca.id
  }

  ingress {
    external_enabled = true   # this one IS public — the direct equivalent of app_sg's 8081 rule
    target_port       = 8081
    traffic_weight {
        percentage = 100
        latest_revision = true
    }
  }

  template {
    container {
      name   = "java-gateway"
      image  = "${data.azurerm_container_registry.shared.login_server}/eai-java-gateway:8231a19d3b6ae1e085a678a02f7da77b4681e39b"
      cpu    = 0.5
      memory = "1Gi"
      env {
        name  = "SERVER_PORT"
        value = "8081"
      }
      env {
        # Container Apps' internal DNS resolves other apps in the same
        # environment by name — this replaces the Docker Compose service
        # name (python-validator) the java-gateway config already expects.
        name  = "INTEGRATION_PYTHON_BASE-URL"
        value = "http://${azurerm_container_app.python_validator.name}"
      }
    }
    min_replicas = 0 # scales to zero when idle — the Consumption-plan trade-off
    max_replicas = 1
  }
}

output "java_gateway_fqdn" { value = azurerm_container_app.java_gateway.latest_revision_fqdn }
