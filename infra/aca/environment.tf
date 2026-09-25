# Goal. A Log Analytics workspace and the Container Apps Environment
# that both Container Apps run inside, on the Consumption plan (no dedicated VNet integration)
# See the free-tier note below.

# Free tier / real production divergence.
# A production Container Apps deployment typically runs inside a Workload Profiles environment
# with custom VNet integration, so the apps sit behind private networking
# and a WAF-fronted Application Gateway rather than the environment's own public ingress.
# That mode has a fixed hourly minimum charge even at zero traffic.
# This window uses the Consumption-only environment: no VNet required,
# billed per-second of actual execution, scales to zero. The trade-off is stated once here
# rather than repeated at each stage: everything below is reachable on the public internet
# through the environment's own managed ingress, exactly as the existing EC2/API-Gateway
# and VM/APIM paths already are.

resource "azurerm_log_analytics_workspace" "poc" {
  name                = "poc-eai-law"
  location            = azurerm_resource_group.poc_aca.location
  resource_group_name = azurerm_resource_group.poc_aca.name
  sku                 = "PerGB2018"   # the current, and only, SKU choice for a new workspace — the
                                        # old dedicated "Free" SKU cannot be created for new workspaces
                                        # any more. "PerGB2018" is not itself a free-tier name; it is
                                        # pay-as-you-go per GB ingested, past whatever free monthly
                                        # allowance Azure currently grants under Azure Monitor's
                                        # "always free" services — worth confirming the current figure
                                        # directly (Azure Pricing Calculator, or Cost Management once
                                        # data starts flowing) rather than assuming a number here.
  retention_in_days   = 30   # kept at/under the typical included retention window, so retention
                                # itself is not a second, separate cost past ingestion
  daily_quota_gb      = 1    # a hard cap, independent of whatever the free allowance turns out to
                                # be: once 1 GB is ingested in a rolling day, further ingestion simply
                                # stops rather than continuing to bill — the safety net for a bounded
                                # learning exercise that has no legitimate reason to ingest that much
                                # in a day regardless. Raised (or removed) deliberately, never left in
                                # place by accident, if a later phase genuinely needs more headroom.
}

resource "azurerm_container_app_environment" "poc" {
  name                       = "poc-eai-aca-env"
  location                   = azurerm_resource_group.poc_aca.location
  resource_group_name        = azurerm_resource_group.poc_aca.name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.poc.id
  # No `infrastructure_subnet_id` set — Consumption-only mode, no VNet required.

  # Declared explicitly because Azure's own control plane auto-populates
  # this profile onto every environment now, Consumption-only ones
  # included, whether or not it is declared here. Leaving it undeclared
  # does not avoid it — it only means every future `terraform plan` shows
  # Azure's real state (this block) as a diff against Terraform's belief
  # (no block), and proposes removing something Azure will just re-add.
  # `minimum_count`/`maximum_count` are not set: they apply to a Dedicated
  # workload profile's fixed node count, not to Consumption, which Azure
  # reports as 0/0 for this profile type regardless of what is set here.
  workload_profile {
    name                  = "Consumption"
    workload_profile_type = "Consumption"
  }
}

output "aca_environment_id"           { value = azurerm_container_app_environment.poc.id }
output "log_analytics_workspace_id"   { value = azurerm_log_analytics_workspace.poc.id }
