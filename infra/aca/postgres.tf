# Globally unique across Azure, lowercase letters and numbers only, 3-24
# chars — pick your own suffix, matching the pattern the Key Vault name
# already uses elsewhere in this root.

# Ideally the following 3 commented resources and the volume_mounts and volume
# should have been the configuration.
# Azure Files (Standard, SMB) doesn't fully support the POSIX
# ownership/permission changes initdb performs on its data directory.
# It's a known mismatch between Postgres and SMB-backed storage.
# The real fix — a Premium Azure Files share with the NFS protocol instead of SMB,
# which does support proper POSIX permissions — needs a FileStorage-kind
# Premium storage account, billed on provisioned capacity with a large practical minimum,
# not the pay-as-you-go Standard tier.
# As a result of this, We loose the ability of filesystem persistence. Data resets
# on every terraform apply that touches the Postgres app, not just on scale-to-zero. 
# Locally, Compose's own named volume (postgres_persistent_engine_data)
# is unaffected and stays persistent
# resource "azurerm_storage_account" "aca" {
#   name                     = "pocaaistgglbunq"
#   resource_group_name      = azurerm_resource_group.poc_aca.name
#   location                 = azurerm_resource_group.poc_aca.location
#   account_tier             = "Standard"
#   account_replication_type = "LRS"
# }

# resource "azurerm_storage_share" "postgres_data" {
#   name                 = "postgres-data"
#   storage_account_id   = azurerm_storage_account.aca.id
#   quota                = 5   # GB — comfortably above what this POC's data will ever reach
# }

# resource "azurerm_container_app_environment_storage" "postgres_data" {
#   name                         = "postgres-data"
#   container_app_environment_id = azurerm_container_app_environment.poc.id
#   account_name                 = azurerm_storage_account.aca.name
#   share_name                   = azurerm_storage_share.postgres_data.name
#   access_key                   = azurerm_storage_account.aca.primary_access_key
#   access_mode                  = "ReadWrite"
# }

resource "azurerm_container_app" "postgres" {
  name                         = "poc-eai-postgres"
  container_app_environment_id = azurerm_container_app_environment.poc.id
  resource_group_name          = azurerm_resource_group.poc_aca.name
  revision_mode                = "Single"
  workload_profile_name        = "Consumption"

  # Needed to resolve the Key Vault secret reference below, exactly as
  # python_validator's own identity block already does — not needed for
  # a registry pull, since postgres:16-alpine comes from the public
  # Docker Hub, not eaisharedacr, so no registry{} block is declared here.
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.aca.id]
  }

  ingress {
    external_enabled = false
    target_port       = 5432
    transport         = "tcp"   # Postgres is not HTTP — the default HTTP ingress mode does not apply here
    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }

  secret {
    name                = "database-password"
    key_vault_secret_id = azurerm_key_vault_secret.db_password.id
    identity             = azurerm_user_assigned_identity.aca.id
  }

  template {
    container {
      name   = "postgres"
      image  = "postgres:16-alpine"
      cpu    = 0.5
      memory = "1Gi"
      env {
        name  = "POSTGRES_USER"
        value = "smart_meter_admin"
      }
      env {
        name        = "POSTGRES_PASSWORD"
        secret_name = "database-password"
      }
      env {
        name  = "POSTGRES_DB"
        value = "smart_meter_warehouse"
      }
      # volume_mounts {
      #   name = "postgres-data"
      #   path = "/var/lib/postgresql/data"
      # }
    }
    # volume {
    #   name         = "postgres-data"
    #   storage_type = "AzureFile"
    #   storage_name = azurerm_container_app_environment_storage.postgres_data.name
    # }
    # A database is the one app in this environment that never scales to
    # zero, and never scales past one: scaling to zero drops the only
    # connection pool and risks an unclean shutdown mid-write; scaling
    # above one would mean two Postgres processes writing to the same
    # file-backed volume, which corrupts the data directory rather than
    # sharing load the way a stateless app safely does.
    min_replicas = 1
    max_replicas = 1
  }
}

output "postgres_internal_hostname" { value = azurerm_container_app.postgres.name }
