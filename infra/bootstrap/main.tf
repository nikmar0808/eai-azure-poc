terraform {
  required_providers {
    azuread = { source = "hashicorp/azuread", version = "~> 3.0" }
    azurerm = { source = "hashicorp/azurerm", version = "~> 4.0" }
  }
  required_version = ">= 1.5.0"
}

provider "azuread" {}

# # Passing subscription_id and tenant_id explicitly is required for the bootstrap workspace
# # because it does not have a resource group yet, so the provider cannot infer them from a resource group.
# # The other workspaces can omit these values because they have a resource group and the provider can infer them from that.
# # Commented out because the bootstrap workspace is now using a resource group in the shared workspace,
# # so the provider can infer subscription_id and tenant_id from that resource group.
# provider "azurerm" {
#   features {}
#   subscription_id = var.azure_subscription_id
#   tenant_id       = var.azure_tenant_id
# }

# --- GitHub Actions deployment identities ---
# THREE separate Entra applications — one per environment — not one
# application with three federated credentials. RBAC in Entra is scoped to
# the service principal, not to which federated credential authenticated
# it; a single shared application would mean any RBAC grant made to it
# (see each environment's identity.tf) is usable regardless of which
# environment's GitHub context obtained the token, defeating the
# per-environment isolation required by ARCHITECTURE_AZURE.md, Design
# Principle 4: a separate principal per environment, not a separate trust
# condition on one shared principal. (The AWS implementation, by contrast,
# uses a single gha-deploy-role.)

resource "azuread_application" "gha_deploy_dev" {
  display_name = "gha-deploy-dev-identity-poc"
}
resource "azuread_service_principal" "gha_deploy_dev" {
  client_id = azuread_application.gha_deploy_dev.client_id
}
resource "azuread_application_federated_identity_credential" "gha_deploy_dev_ref" {
  application_id = azuread_application.gha_deploy_dev.id
  display_name   = "github-actions-dev-ref"
  description    = "GitHub Actions OIDC — dev build/push jobs (no environment: key, push-triggered on develop)"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:${var.github_org}@${var.github_owner_id}/${var.repo_name}@${var.github_repo_id}:ref:refs/heads/develop"
}

# A second, separate credential — Entra federated credentials match exactly
# one subject each (unlike AWS IAM's StringLike, which accepts an array).
# The docker-build-push jobs (no `environment:` key) receive a
# ref:refs/heads/BRANCH-shaped claim and authenticate via the credential
# above; the deploy-dev job declares `environment: dev` and receives an
# environment:NAME-shaped claim instead, regardless of branch — it needs
# this second credential or it fails OIDC even though the build jobs work.
resource "azuread_application_federated_identity_credential" "gha_deploy_dev" {
  application_id = azuread_application.gha_deploy_dev.id
  display_name   = "github-actions-dev-environment"
  description    = "GitHub Actions OIDC — deploy-dev job (declares environment: dev)"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:${var.github_org}@${var.github_owner_id}/${var.repo_name}@${var.github_repo_id}:environment:dev"
}

resource "azuread_application" "gha_deploy_uat" {
  display_name = "gha-deploy-uat-identity-poc"
}
resource "azuread_service_principal" "gha_deploy_uat" {
  client_id = azuread_application.gha_deploy_uat.client_id
}
resource "azuread_application_federated_identity_credential" "gha_deploy_uat" {
  application_id = azuread_application.gha_deploy_uat.id
  display_name   = "github-actions-uat"
  description    = "GitHub Actions OIDC — uat environment deployments"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  # A workflow_dispatch-triggered job declaring `environment: uat` receives
  # this claim shape, not a ref:refs/heads/BRANCH shape.
  subject        = "repo:${var.github_org}@${var.github_owner_id}/${var.repo_name}@${var.github_repo_id}:environment:uat"
}

resource "azuread_application" "gha_deploy_prod" {
  display_name = "gha-deploy-prod-identity-poc"
}
resource "azuread_service_principal" "gha_deploy_prod" {
  client_id = azuread_application.gha_deploy_prod.client_id
}
resource "azuread_application_federated_identity_credential" "gha_deploy_prod" {
  application_id = azuread_application.gha_deploy_prod.id
  display_name   = "github-actions-prod"
  description    = "GitHub Actions OIDC — prod environment deployments"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:${var.github_org}@${var.github_owner_id}/${var.repo_name}@${var.github_repo_id}:environment:prod"
}

# --- HCP Terraform identities ---
# Three separate Entra applications, one per workspace (dev, uat, prod), each
# trusting only its own workspace. No RBAC is granted to any of them under
# Local execution mode, because HCP Terraform never itself runs plan or apply.

resource "azuread_application" "tfc_run_dev" {
  display_name = "tfc-run-dev-identity-poc"
}

resource "azuread_service_principal" "tfc_run_dev" {
  client_id = azuread_application.tfc_run_dev.client_id
}

resource "azuread_application_federated_identity_credential" "tfc_run_dev" {
  application_id = azuread_application.tfc_run_dev.id
  display_name   = "hcp-terraform-workload-identity"
  description    = "HCP Terraform OIDC — plan/apply runs for the dev workspace"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://app.terraform.io"
  subject        = "organization:${var.hcp_terraform_org}:project:*:workspace:${var.hcp_terraform_ws_dev}:run_phase:*"
}

resource "azuread_application" "tfc_run_uat" {
  display_name = "tfc-run-uat-identity-poc"
}

resource "azuread_service_principal" "tfc_run_uat" {
  client_id = azuread_application.tfc_run_uat.client_id
}

resource "azuread_application_federated_identity_credential" "tfc_run_uat" {
  application_id = azuread_application.tfc_run_uat.id
  display_name   = "hcp-terraform-workload-identity"
  description    = "HCP Terraform OIDC — plan/apply runs for the uat workspace"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://app.terraform.io"
  subject        = "organization:${var.hcp_terraform_org}:project:*:workspace:${var.hcp_terraform_ws_uat}:run_phase:*"
}

resource "azuread_application" "tfc_run_prod" {
  display_name = "tfc-run-prod-identity-poc"
}

resource "azuread_service_principal" "tfc_run_prod" {
  client_id = azuread_application.tfc_run_prod.client_id
}

resource "azuread_application_federated_identity_credential" "tfc_run_prod" {
  application_id = azuread_application.tfc_run_prod.id
  display_name   = "hcp-terraform-workload-identity"
  description    = "HCP Terraform OIDC — plan/apply runs for the prod workspace"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://app.terraform.io"
  subject        = "organization:${var.hcp_terraform_org}:project:*:workspace:${var.hcp_terraform_ws_prod}:run_phase:*"
}

# No RBAC role assignments are created here — that happens once each
# environment's resource group exists (in each environment's identity.tf), which is exactly the
# circularity this bootstrap step exists to break.

output "gha_deploy_dev_client_id"  { value = azuread_application.gha_deploy_dev.client_id }
output "gha_deploy_uat_client_id"  { value = azuread_application.gha_deploy_uat.client_id }
output "gha_deploy_prod_client_id" { value = azuread_application.gha_deploy_prod.client_id }
output "tfc_run_dev_client_id"         { value = azuread_application.tfc_run_dev.client_id }
output "tfc_run_uat_client_id"         { value = azuread_application.tfc_run_uat.client_id }
output "tfc_run_prod_client_id"         { value = azuread_application.tfc_run_prod.client_id }
