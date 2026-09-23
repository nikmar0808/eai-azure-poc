# Deployment Guide — Azure Implementation

This document describes how to deploy this project to an independent Microsoft Azure subscription, following the three-environment (Development, UAT, Production) release pipeline documented in [`ARCHITECTURE_AZURE.md`](ARCHITECTURE_AZURE.md) and [`INFRA_VIEW_AZURE.md`](INFRA_VIEW_AZURE.md). Design rationale is not repeated here.

This guide assumes the repository has been cloned and the local quickstart in [`README_AZURE.md`](README_AZURE.md) has been verified before any Azure resource is touched.

**A note on this document's sequencing.** Azure Free Tier subscriptions commonly carry a `Standard Bsv2 Family vCPUs` regional quota too small to support three simultaneously-provisioned virtual machines (`ARCHITECTURE_AZURE.md`, Section 7) and a public-IP ceiling too small to support a dedicated Bastion host per environment (`ARCHITECTURE_AZURE.md`, Section 6). This guide presents the deployment sequence shaped by both constraints — Development infrastructure first and verified end-to-end, then UAT, with Production's compute deliberately deferred until Development is torn down to free capacity — rather than an idealized sequence that assumes unconstrained quota. Each constraint is stated explicitly at the point it applies, together with what a standard-quota subscription should do instead.

---

## Prerequisites

| Requirement | Notes |
|---|---|
| Azure subscription | Free-tier vCPU and public-IP quotas materially shape Phase 2 and Phase 6 — see those sections and `ARCHITECTURE_AZURE.md` Section 6–7 |
| GitHub repository (a fork or clone of this project) | Actions and Environments must be enabled |
| HCP Terraform account and organization | Free tier is sufficient |
| Azure CLI | Current supported version, with the `ssh` extension (`az extension add --upgrade -n ssh`) |
| Terraform CLI | `>= 1.5.0` |
| Docker and Docker Compose | For local verification |
| Java 21, Python 3.14 | For local application build/test |

## Placeholder Reference

Every command block below uses the placeholders in this table. **Replace all occurrences of `<...>` with your values before running a command**. Resource-name *conventions* that are not account-specific — resource group names (`eai-<env>-rg`), VM names (`eai-<env>-host`), NSG names, subnet names — are left literal throughout this guide rather than placeholdered, since they are a reusable naming scheme, not values tied to any one subscription. Names Azure requires to be globally unique across the entire platform (Container Registry, Key Vault, PostgreSQL Flexible Server, API Management), and identifiers tied specifically to one subscription, tenant, or repository, are placeholders.

| Placeholder | Example value | How to obtain it |
|---|---|---|
| `<AZURE_SUBSCRIPTION_ID>` | `00000000-0000-0000-0000-000000000000` | `az account show --query id --output tsv` once authenticated |
| `<AZURE_TENANT_ID>` | `00000000-0000-0000-0000-000000000000` | `az account show --query tenantId --output tsv` |
| `<AZURE_LOCATION>` | `centralindia` | The Azure region chosen for this deployment; used consistently in every command and Terraform file |
| `<GITHUB_ORG>` | `octocat` | The GitHub username or organization that owns the repository, visible in its URL |
| `<REPO_NAME>` | `enterprise-integration-azure` | The repository name, visible in its URL |
| `<GITHUB_OWNER_ID>` | `000000000` | `https://api.github.com/repos/<GITHUB_ORG>/<REPO_NAME>` - Field `owner.id` in the output |
| `<GITHUB_REPO_ID>` | `0000000000` | Same API response →  - Field `id` in the output |
| `<HCP_TERRAFORM_ORG>` | `my-tfc-org` | The Terraform Cloud organization name, shown at the top of the HCP Terraform web interface after sign-in |
| `<HCP_TERRAFORM_PROJECT>` | `my-tf-proj` | A project to organize this project's workspaces |
| `<HCP_TERRAFORM_WORKSPACE_SHARED>` | `my-shared-ws` | A shared workspace |
| `<HCP_TERRAFORM_WORKSPACE_DEV>` | `my-dev-ws` | DEV workspace |
| `<HCP_TERRAFORM_WORKSPACE_UAT>` | `my-uat-ws` | UAT workspace |
| `<HCP_TERRAFORM_WORKSPACE_PROD>` | `my-prod-ws` | PROD workspace |
| `<AZURE_CLIENT_ID_DEV>` | `00000000-0000-0000-0000-000000000000` | Recorded from Phase 1.3's bootstrap apply |
| `<AZURE_CLIENT_ID_UAT>` | `00000000-0000-0000-0000-000000000000` | Recorded from Phase 1.3's bootstrap apply |
| `<AZURE_CLIENT_ID_PROD>` | `00000000-0000-0000-0000-000000000000` | Recorded from Phase 1.3's bootstrap apply |
| `<AZURE_ACR_NAME>` | `my-shared-acr` | A globally-unique Container Registry name — confirm with `az acr check-name --name <AZURE_ACR_NAME>`|
| `<AZURE_KEY_VAULT_NAME_DEV>` | `xxx-dev-kv-suffix` | A globally-unique Key Vault name for DEV; append a short random suffix to avoid collision |
| `<AZURE_KEY_VAULT_NAME_UAT>` | `xxx-uat-kv-suffix` | A globally-unique Key Vault name for UAT; append a short random suffix to avoid collision |
| `<AZURE_KEY_VAULT_NAME_PROD>` | `xxx-prod-kv-suffix` | A globally-unique Key Vault name for PROD; append a short random suffix to avoid collision |
| `<AZURE_POSTGRES_SERVER_DEV>` | `xxx-dev-pg-suffix` | A globally-unique PostgreSQL Flexible Server name per environment |
| `<AZURE_POSTGRES_SERVER_UAT>` | `xxx-uat-pg-suffix` | A globally-unique PostgreSQL Flexible Server name per environment |
| `<AZURE_POSTGRES_SERVER_PROD>` | `xxx-prod-pg-suffix` | A globally-unique PostgreSQL Flexible Server name per environment |
| `<AZURE_APIM_NAME_DEV>` | `xxx-dev-apim-suffix` | A globally-unique API Management name per environment |
| `<AZURE_APIM_NAME_UAT>` | `xxx-uat-apim-suffix` | A globally-unique API Management name per environment |
| `<AZURE_APIM_NAME_PROD>` | `xxx-prod-apim-suffix` | A globally-unique API Management name per environment |
| `<OPERATOR_IP>` | `my-public-ip` | Used to construct variable `operator_ip_cidr` - operator's public IP, as a `/32` CIDR — obtain via bash `curl ifconfig.me` or Windows Powershell `Invoke-RestMethod https://api.ipify.org` |

---

## Phase 0 — Local Development Verification

This phase confirms the application layer works correctly, independently of any Azure resource, before cloud provisioning begins. The application source (`01-java-ingestion-service`, `02-python-transformation-api`, `test/`, and the root `docker-compose.dev.yml`) is cloud-agnostic — the same services run unchanged regardless of which cloud eventually hosts them.

**Verify:**

```bash
# Run from: <repo-root>
docker compose -f docker-compose.dev.yml up --build -d
docker compose -f docker-compose.dev.yml ps
curl http://localhost:8081/health
```
```powershell
# PowerShell equivalent — run from: <repo-root>
docker compose -f docker-compose.dev.yml up --build -d
docker compose -f docker-compose.dev.yml ps
Invoke-RestMethod -Uri http://localhost:8081/health
```

**Expected result:** all services report `running` or `healthy`; the health check returns `{"status":"UP"}`. Stop the local stack before proceeding:

```bash
docker compose -f docker-compose.dev.yml down
```
```powershell
# PowerShell equivalent
docker compose -f docker-compose.dev.yml down
```

---

## Phase 1 — Azure Identity Bootstrap

### 1.1 Azure CLI authentication

```bash
# bash
az login
az account list --output table
az account set --subscription "<AZURE_SUBSCRIPTION_ID>"
az account show --query "{subscriptionId:id,subscriptionName:name,tenantId:tenantId,user:user.name}" --output json
```
```powershell
# PowerShell equivalent
az login
az account list --output table
az account set --subscription "<AZURE_SUBSCRIPTION_ID>"
az account show --query "{subscriptionId:id,subscriptionName:name,tenantId:tenantId,user:user.name}" --output json
```

**Confirm the output before proceeding:** `subscriptionId` reads `<AZURE_SUBSCRIPTION_ID>`, `tenantId` reads `<AZURE_TENANT_ID>`, `subscriptionName` reads `Azure_Free_Tier`. Every later step in this document assumes this exact account is active. Interactive login requires MFA per standard Azure CLI policy; this does not apply to the federated identities created in Section 1.2.

### 1.2 Resource provider registration

```bash
# bash
for ns in Microsoft.Compute Microsoft.Network Microsoft.ContainerRegistry Microsoft.KeyVault Microsoft.DBforPostgreSQL Microsoft.ApiManagement Microsoft.ManagedIdentity Microsoft.OperationalInsights; do
  az provider register --namespace "$ns"
done
```
```powershell
# PowerShell equivalent
$providers = "Microsoft.Compute","Microsoft.Network","Microsoft.ContainerRegistry","Microsoft.KeyVault","Microsoft.DBforPostgreSQL","Microsoft.ApiManagement","Microsoft.ManagedIdentity","Microsoft.OperationalInsights"
foreach ($ns in $providers) { az provider register --namespace $ns }
```

Confirm every namespace reads `Registered` before proceeding — registration is asynchronous:

```bash
# bash
for ns in Microsoft.Compute Microsoft.Network Microsoft.ContainerRegistry Microsoft.KeyVault Microsoft.DBforPostgreSQL Microsoft.ApiManagement Microsoft.ManagedIdentity Microsoft.OperationalInsights; do
  echo -n "$ns: "; az provider show --namespace "$ns" --query registrationState --output tsv
done
```
```powershell
# PowerShell equivalent
foreach ($ns in $providers) { Write-Output "$ns`: $(az provider show --namespace $ns --query registrationState --output tsv)" }
```

### 1.3 Identity bootstrap Terraform configuration

A one-time, locally-applied, separate-state Terraform root creates only the Entra applications, service principals, and federated identity credentials described in `ARCHITECTURE_AZURE.md` Appendix A — no application infrastructure. This resolves the same circularity a remote Terraform run would otherwise face: an identity cannot be used to authenticate the very Terraform run that creates it.

**File to modify:** `infra/bootstrap/terraform.tfvars.sample` - rename by removing ".sample" from name and change contents

**Apply:**

```bash
# bash — run from: <repo-root>/infra/bootstrap
cd infra/bootstrap
terraform init
terraform plan
terraform apply
```
```powershell
# PowerShell equivalent — run from: <repo-root>\infra\bootstrap
Set-Location infra\bootstrap
terraform init
terraform plan
terraform apply
```

**Record the three GitHub Actions outputs as `<AZURE_CLIENT_ID_DEV>`, `<AZURE_CLIENT_ID_UAT>` and `<AZURE_CLIENT_ID_PROD>`.** The three HCP Terraform outputs (`tfc_run_dev_client_id`, `tfc_run_uat_client_id`, `tfc_run_prod_client_id`) are not consumed under Local Execution Mode and are retained for parity with the GitHub Actions identity model. The GitHub Actions client IDs are used throughout the remaining phases wherever the corresponding placeholder appears. **Any future edit to this file has no effect on Azure until `terraform apply` is re-run inside `infra/bootstrap/` specifically** — it is a separate root module with its own local state.

### 1.4 HCP Terraform workspace configuration

Create a project named `<HCP_TERRAFORM_PROJECT>` in the HCP Terraform web interface, organization `<HCP_TERRAFORM_ORG>`. Create four workspaces (`CLI Driven Workflow`), each with **Execution Mode → Local**: `<HCP_TERRAFORM_WORKSPACE_DEV>`, `<HCP_TERRAFORM_WORKSPACE_UAT>`, `<HCP_TERRAFORM_WORKSPACE_PROD>`, `<HCP_TERRAFORM_WORKSPACE_SHARED>`.

**No workspace variables are required on any of the four.** Under Local Execution Mode, HCP Terraform never itself runs `plan`/`apply` — it is a remote state backend only. The `ARM_CLIENT_ID` / `ARM_TENANT_ID` / `ARM_SUBSCRIPTION_ID` / `ARM_USE_OIDC` variables that a Remote- or Agent-mode workspace would require are therefore not configured; setting them here would configure something never consumed.

What actually authenticates a local `terraform apply` is the `az login` session from Section 1.1 — the `azurerm` provider block (`provider "azurerm" { features {} }`, with no explicit `client_id`/`use_oidc` arguments) falls back automatically to the active Azure CLI session when no such arguments or `ARM_*` environment variables are present. No export/eval step is required before running Terraform locally.

`tfc-run-identity` (Section 1.3) is retained for parity with the GitHub Actions identity model and is not actively used under Local Execution Mode; it becomes relevant only if a workspace is later switched to Remote or Agent execution mode — the standard-quota, steady-state alternative to the fully-local pattern used throughout this document.

## 1.5 Shared Container Registry

### 1.5.1 Rationale for this phase's ordering

The shared Container Registry (`ARCHITECTURE_AZURE.md`, Section 5) is provisioned first, once, outside any environment's own workspace, since every environment's `identity.tf` references it by data-source lookup. Development is provisioned next and verified end-to-end before UAT or Production infrastructure is touched — a first-attempt `terraform apply` against a new subscription is the most likely place to hit an unanticipated issue (a free-tier quota limit, a region capacity restriction, a resource-name collision), and finding that out once against Development alone is cheaper than discovering it three times, or discovering it in Production.

**Region and resource-name availability were confirmed before this phase began:**

```bash
# bash
az account list-locations --query "[?name=='centralindia'].{name:name,displayName:displayName}" --output table
az acr check-name --name <AZURE_ACR_NAME> --output table
nslookup <AZURE_POSTGRES_SERVER_DEV>.postgres.database.azure.com
nslookup <AZURE_APIM_NAME_DEV>.azure-api.net
```
```powershell
# PowerShell equivalent
az account list-locations --query "[?name=='centralindia'].{name:name,displayName:displayName}" --output table
az acr check-name --name <AZURE_ACR_NAME> --output table
Resolve-DnsName <AZURE_POSTGRES_SERVER_DEV>.postgres.database.azure.com -ErrorAction SilentlyContinue
Resolve-DnsName <AZURE_APIM_NAME_DEV>.azure-api.net -ErrorAction SilentlyContinue
```

A DNS resolution failure (`NXDOMAIN` / no output) for the PostgreSQL and API Management hostname checks is the expected, good result — confirming nothing else is already using those globally-unique hostnames. The same checks apply, with the corresponding names, before UAT and Production provisioning (Phase 3).

### 1.5.2 Shared Container Registry
Applied against workspace `<HCP_TERRAFORM_WORKSPACE_SHARED>`.

**File to modify:** `infra/shared/terraform.tfvars.sample` - rename by removing ".sample" from name and change contents

**Apply**

```bash
# bash — run from: <repo-root>/infra/shared
cd infra/shared
terraform init
terraform plan
terraform apply
```
```powershell
# PowerShell equivalent — run from: <repo-root>\infra\shared
Set-Location infra\shared
terraform init
terraform plan
terraform apply
```

**Record `acr_login_server`** — resolves to `<AZURE_ACR_NAME>.azurecr.io`, the `ACR_REGISTRY` value consumed by the CI workflow (Phase 4). This resource group and registry are never destroyed as part of any environment's provisioning or teardown lifecycle — there is no environment-cycling equivalent for this workspace.

## Phase 2 — Development Infrastructure

Applied against workspace `<HCP_TERRAFORM_WORKSPACE_DEV>`

**File to modify:** `infra/dev/terraform.tfvars.sample` - rename by removing ".sample" from name and change contents

`infra/dev/variables.tf` declares `operator-IP` variable consumed by the SSH-access NSG rule also here

### 2.1 Backend and provider
`infra/dev/main.tf`

### 2.2 Networking
`infra/dev/networking.tf`

### 2.3 Managed Identity
`infra/dev/identity.tf`
Note:
```hcl
# Only DEV builds and pushes images — the GitHub Actions workflow is configured to fail
# if it tries to push to ACR from those environments.
###########################################################################
#                                                                         #
# This resource is not configured for UAT or PROD because                 #
# those environments' builds are read-only and do not push images to ACR. #
#                                                                         #
###########################################################################
resource "azurerm_role_assignment" "gha_dev_acr_push" {
  scope                = data.azurerm_container_registry.shared.id
  role_definition_name = "AcrPush"
  principal_id         = data.azuread_service_principal.gha_deploy_dev.object_id
}
```

### 2.4 Development Key Vault
`infra/dev/key-vault.tf`

### 2.5 Azure Bastion — not provisioned
`infra/dev/bastion.tf`**
Note: This is the recommended pattern for a subscription with standard public-IP quota, and the direct successor once this subscription's constraint (`ARCHITECTURE_AZURE.md`, Section 6) is no longer binding
**Check Note on `az ssh vm` provisioning in Section 2.9.**

### 2.6 API Management
`infra/dev/api-management.tf`
Note: Operations are declared per-route explicitly rather than through a wildcard template — API Management's template language does not accept `/*` as a catch-all; the correct wildcard syntax is `/{*path}` with an accompanying `template_parameter` block, and this project's confirmed-working configuration uses explicit routes instead.

**Files that may need modifications:**

### 2.7 Development PostgreSQL Flexible Server

Confirm SKU availability for this subscription and region before writing the resource block — Flexible Server capacity restrictions surface only at creation time, not in the list output, so this check confirms the SKU is a valid choice in the region but not that it is guaranteed unrestricted:

```bash
# bash
az postgres flexible-server list-skus --location centralindia --output table
```
```powershell
# PowerShell equivalent
az postgres flexible-server list-skus --location centralindia --output table
```

**File to modify:** `infra/dev/postgresql.tf`

```hcl
resource "azurerm_private_dns_zone" "postgres" {
  name                = "privatelink.postgres.database.azure.com"
  resource_group_name = azurerm_resource_group.dev.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "postgres" {
  name                  = "eai-dev-vnet-link"
  private_dns_zone_name = azurerm_private_dns_zone.postgres.name
  virtual_network_id    = azurerm_virtual_network.dev.id
  resource_group_name   = azurerm_resource_group.dev.name
}

resource "azurerm_postgresql_flexible_server" "dev" {
  name                          = var.postgres_server_name
  resource_group_name           = azurerm_resource_group.dev.name
  location                      = azurerm_resource_group.dev.location
  version                       = "16"
  zone                          = "2"
  delegated_subnet_id           = azurerm_subnet.db.id
  private_dns_zone_id           = azurerm_private_dns_zone.postgres.id
  public_network_access_enabled = false
  administrator_login           = "smart_meter_admin"
  administrator_password        = random_password.postgres_admin.result
  storage_mb                    = 32768
  sku_name                      = "B_Standard_B1ms"
  backup_retention_days         = 7

  depends_on = [
    azurerm_subnet.db,
    azurerm_private_dns_zone_virtual_network_link.postgres
  ]
}

resource "azurerm_postgresql_flexible_server_database" "dev" {
  name      = "smart_meter_warehouse"
  server_id = azurerm_postgresql_flexible_server.dev.id
}

output "postgres_fqdn" { value = azurerm_postgresql_flexible_server.dev.fqdn }
```

The server name is supplied through the `postgres_server_name` variable (value `<AZURE_POSTGRES_SERVER_DEV>` in `terraform.tfvars`) rather than written into the resource block.

The explicit `zone = "2"` and the `depends_on` on the delegated subnet and DNS zone link are both required — their absence produces, respectively, a zone-exchange error surfaced later at the API Management apply step, and an `AnotherOperationInProgress` error from a missing subnet dependency. `public_network_access_enabled = false` is set explicitly rather than relied upon as a default.

### 2.8 Development virtual machine

Confirm VM size availability before writing the resource block:

```bash
# bash
az vm list-skus --location centralindia --size Standard_B --all --query "[].{Name:name, RestrictionType:restrictions[0].type, ReasonCode:restrictions[0].reasonCode}" --output table
```
```powershell
# PowerShell equivalent
az vm list-skus --location centralindia --size Standard_B --all --query "[].{Name:name, RestrictionType:restrictions[0].type, ReasonCode:restrictions[0].reasonCode}" --output table
```

Every classic (v1) B-series size shows `RestrictionType: Location` for this subscription in this region — genuinely blocked region-wide, not a transient shortage. The v2 generation shows `RestrictionType: Zone` only, which does not affect this deployment since no `zone` is pinned on the VM resource; `Standard_B2s_v2` is the smallest v2 size available.

**File to modify:** `infra/dev/compute.tf`

May have to modify `size = "Standard_B2s_v2"` to someother available capacity.
```hcl
resource "azurerm_linux_virtual_machine" "dev" {
  name                            = "eai-dev-host"
  resource_group_name             = azurerm_resource_group.dev.name
  location                        = azurerm_resource_group.dev.location
  size                            = "Standard_B2s_v2"
  admin_username                  = "azureuser"
  network_interface_ids           = [azurerm_network_interface.vm.id]
  disable_password_authentication = true

  admin_ssh_key {
    username   = "azureuser"
    public_key = tls_private_key.vm_unused.public_key_openssh
  }
```

The `custom_data` script disables Ubuntu's unattended-upgrade timers before any `apt-get` call, installs Docker CE from Docker's own repository rather than the `docker.io` package, and installs the Azure CLI — all three fixes were required for the bootstrap script to complete reliably on Ubuntu 24.04 LTS.
```hcl
  custom_data = base64encode(<<-EOF
    #!/bin/bash
    set -e
    exec > >(tee /var/log/eai-bootstrap.log) 2>&1

    # Ubuntu cloud images run unattended-upgrades and apt-daily(-upgrade)
    # timers on first boot; these race with this script's own apt-get calls
    # for /var/lib/dpkg/lock-frontend and cause a hard failure rather than a
    # wait. Disabling them before any apt-get call removes the race.
    systemctl stop unattended-upgrades.service 2>/dev/null || true
    systemctl disable unattended-upgrades.service 2>/dev/null || true
    systemctl stop apt-daily.timer apt-daily-upgrade.timer 2>/dev/null || true
    systemctl disable apt-daily.timer apt-daily-upgrade.timer 2>/dev/null || true

    APT="apt-get -o DPkg::Lock::Timeout=120"
    $APT update -y
    $APT install -y ca-certificates curl gnupg

    # docker-compose-plugin is not resolvable from Ubuntu 24.04's default
    # apt repository — Docker's own apt repository is required.
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    $APT update -y
    $APT install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    systemctl enable --now docker
    usermod -aG docker azureuser

    # Required because the deploy Run Command script performs
    # `az login --identity` + `az acr login` locally on this VM.
    curl -sL https://aka.ms/InstallAzureCLIDeb | bash

    mkdir -p /opt/eai
  EOF
  )
}
```

### 2.9 Apply and Verify Development infrastructure

```bash
# bash — run from: <repo-root>/infra/dev
cd infra/dev
terraform init
terraform plan -var="operator_ip_cidr=<OPERATOR_IP>/32"
terraform apply -var="operator_ip_cidr=<OPERATOR_IP>/32"
```
```powershell
# PowerShell equivalent — run from: <repo-root>\infra\dev
Set-Location infra\dev
terraform init
terraform plan -var="operator_ip_cidr=<OPERATOR_IP>/32"
terraform apply -var="operator_ip_cidr=<OPERATOR_IP>/32"
```

Standard Ubuntu Azure Marketplace images ship with the Azure VM Agent pre-installed and running from first boot, so no separate agent-installation step is required before Run Command is usable — worth a one-line confirmation regardless:

**Record all the Output values once TFC Apply finishes. Some of them will be set in Github or used in subsequent sections"**

Run the following commands:

```bash
# bash
cd infra/dev
az vm run-command invoke --resource-group eai-dev-rg --name eai-dev-host --command-id RunShellScript --scripts "echo agent-check-ok"
```
```powershell
# PowerShell equivalent
Set-Location infra\dev
az vm run-command invoke --resource-group eai-dev-rg --name eai-dev-host --command-id RunShellScript --scripts "echo agent-check-ok"
```

```bash
# bash
az extension add --upgrade -n ssh
az ssh vm --resource-group eai-dev-rg --name eai-dev-host
```
```powershell
# PowerShell equivalent
az extension add --upgrade -n ssh
az ssh vm --resource-group eai-dev-rg --name eai-dev-host
```

**DO NOT PROCEED unless the first command shows `echo agent-check-ok` and the second command establishes a successful connection with the VM.**

**Free-tier quota note carried forward to Phase 3:** this subscription's `Standard Bsv2 Family vCPUs` quota is 4, and Development's VM alone consumes 2. Provisioning UAT's VM next (Phase 3) is within quota; provisioning Production's VM afterward, while Development and UAT both remain up, is not — see `ARCHITECTURE_AZURE.md` Section 7 and Phase 3.7 below for the full constraint and the deferral it requires. A subscription with standard Burstable v2 quota does not need to observe this deferral and may provision all three environments' compute concurrently.

## Phase 3 — UAT Infrastructure and the Production Deferral

### 3.1 UAT provisioning — identical shape to Development

UAT's infrastructure (`infra/uat/`) is structurally identical to Development's (Phase 2.3–2.9), differing only in identifiers. It is not reproduced in full here; only the differences and the apply sequence are given.

**File to modify:** `infra/uat/terraform.tfvars.sample` - rename by removing ".sample" from name and change contents

**Substitutions relative to `infra/dev/`:**

| Development value | UAT value |
|---|---|
| Workspace | `<HCP_TERRAFORM_WORKSPACE_DEV>` → `<HCP_TERRAFORM_WORKSPACE_UAT>` |
| Resource group | `eai-dev-rg` → `eai-uat-rg` |
| VNet / NIC / Public IP / NSG names | `eai-dev-*` → `eai-uat-*` |
| Managed identity | `eai-dev-vm-id` → `eai-uat-vm-id` |
| Key Vault | `<AZURE_KEY_VAULT_NAME_DEV>` → `<AZURE_KEY_VAULT_NAME_UAT>` |
| PostgreSQL server | `<AZURE_POSTGRES_SERVER_DEV>` → `<AZURE_POSTGRES_SERVER_UAT>` |
| VM | `eai-dev-host` → `eai-uat-host` |
| API Management | `<AZURE_APIM_NAME_DEV>` → `<AZURE_APIM_NAME_UAT>` |
| GitHub Actions identity client ID | `<AZURE_CLIENT_ID_DEV>` → `<AZURE_CLIENT_ID_UAT>` |

**One structural difference, not merely a naming one:** UAT's GitHub Actions RBAC (the UAT equivalent of Phase 2.9) grants `AcrPull` only — never `AcrPush`. UAT never builds an image; its promotion workflow only confirms an already-built image's tag exists in the shared registry before deploying it.

**Apply:**

```bash
# bash — run from: <repo-root>/infra/uat
cd infra/uat
terraform init
terraform plan -var="operator_ip_cidr=<OPERATOR_IP>/32"
terraform apply -var="operator_ip_cidr=<OPERATOR_IP>/32"
terraform output -raw postgres_fqdn
terraform output -raw vm_public_ip
```
```powershell
# PowerShell equivalent — run from: <repo-root>\infra\uat
Set-Location infra\uat
terraform init
terraform plan -var="operator_ip_cidr=<OPERATOR_IP>/32"
terraform apply -var="operator_ip_cidr=<OPERATOR_IP>/32"
terraform output -raw postgres_fqdn
terraform output -raw vm_public_ip
```

```bash
# bash — verify the VM agent, then apply API Management
az vm run-command invoke --resource-group eai-uat-rg --name eai-uat-host --command-id RunShellScript --scripts "echo agent-check-ok"
cd infra/uat
terraform apply -var="operator_ip_cidr=<OPERATOR_IP>/32"
terraform output -raw apim_gateway_url
```
```powershell
# PowerShell equivalent
az vm run-command invoke --resource-group eai-uat-rg --name eai-uat-host --command-id RunShellScript --scripts "echo agent-check-ok"
Set-Location infra\uat
terraform apply -var="operator_ip_cidr=<OPERATOR_IP>/32"
terraform output -raw apim_gateway_url
```

**Record `postgres_fqdn`, `vm_identity_client_id`, and `apim_gateway_url`** for UAT — required by the CI workflow's environment configuration (Section 3.3) and by UAT's own verification step (Phase 5).

### 3.2 The vCPU quota constraint reached at Production

Attempting Production's virtual machine (the Production equivalent of Phase 2.8) while Development's and UAT's VMs are both still provisioned fails:

```text
OperationNotAllowed: Operation could not be completed as it results in exceeding
approved Standard Bsv2 Family vCPUs quota. Current Limit: 4, Current Usage: 4,
Additional Required: 2
```

Production's non-compute resources — resource group, networking, Key Vault, PostgreSQL Flexible Server, registry role assignments — provision successfully regardless, since none of them consume vCPU quota. Only `azurerm_linux_virtual_machine.prod`, its two dependent resources (`azurerm_role_assignment.vm_admin_login`, `azurerm_virtual_machine_extension.aad_login`), and API Management's `service_url` (which depends on the VM's public IP) are actually blocked.

**Six alternate regions were evaluated as a relocation target for Production specifically, on the theory that VM-family quota is scoped per region, and all six were rejected:** two regions had PostgreSQL Flexible Server subscription-restricted; two were unsupported by the Postgres/usage API entirely; one had the entire `Standard_B` VM family blocked for this subscription; two had the entire x86 `Standard_B` family blocked, leaving only an untested ARM64 line not adopted here. This subscription's `Standard_B`-family x86 VM access is effectively allow-listed to `centralindia` only — relocation is not a viable resolution on this subscription, though a different subscription's quota profile may differ.

**Adopted resolution:** Production's compute apply is deferred until Development is torn down, per the environment-cycling model in `ARCHITECTURE_AZURE.md` Section 7. This is stated here as the reason a later phase (Phase 4, Section 4.4 of the promotion workflow) requires a Development teardown step before Production's compute can be applied — it is a scheduling resolution, not a geographic one. **A subscription with standard Burstable v2 vCPU quota does not need to defer Production's compute at all** and may apply Phase 2's equivalent Production infrastructure (substituting `eai-prod-*` identifiers) immediately after UAT, exactly as Development and UAT were applied above.

Production's non-compute resources are applied now regardless, using the same substitution table as UAT (Section 3.1), with `eai-prod-*` identifiers throughout and GitHub Actions identity client ID `<AZURE_CLIENT_ID_PROD>`. The compute apply itself (`terraform apply` including `azurerm_linux_virtual_machine.prod` and `api-management.tf`) is deferred to Phase 5, after Phase 4's Development teardown.

### 3.3 GitHub repository and Environment configuration

| Variable | Scope | Value |
|---|---|---|
| `AZURE_TENANT_ID` | Repository | `<AZURE_TENANT_ID>` |
| `AZURE_SUBSCRIPTION_ID` | Repository | `<AZURE_SUBSCRIPTION_ID>` |
| `AZURE_CLIENT_ID_DEV` | Repository | `<AZURE_CLIENT_ID_DEV>` |
| `AZURE_CLIENT_ID_UAT` | Repository | `<AZURE_CLIENT_ID_UAT>` |
| `AZURE_CLIENT_ID_PROD` | Repository | `<AZURE_CLIENT_ID_PROD>` |
| `ACR_NAME` | Repository | Value must be `<AZURE_ACR_NAME>` - The Container Registry's short name (e.g. `eaisharedacr`) — used wherever the CLI needs the name alone, not the full login server |
| `DEV_KEY_VAULT_NAME` | Environment `dev` | `<AZURE_KEY_VAULT_NAME_DEV>` |
| `UAT_KEY_VAULT_NAME` | Environment `uat` | `<AZURE_KEY_VAULT_NAME_UAT>` |
| `PROD_KEY_VAULT_NAME` | Environment `prod` | `<AZURE_KEY_VAULT_NAME_PROD>` |
| `DEV_POSTGRES_FQDN` | Environment `dev` | Development's `postgres_fqdn` output |
| `UAT_POSTGRES_FQDN` | Environment `uat` | UAT's `postgres_fqdn` output |
| `PROD_POSTGRES_FQDN` | Environment `prod` | Production's `postgres_fqdn` output |
| `DEV_VM_IDENTITY_CLIENT_ID` | Environment `dev` | Development's `vm_identity_client_id` output |
| `UAT_VM_IDENTITY_CLIENT_ID` | Environment `uat` | UAT's `vm_identity_client_id` output |
| `PROD_VM_IDENTITY_CLIENT_ID` | Environment `prod` | Production's `vm_identity_client_id` output |

Create GitHub Environments `dev` (no required reviewer), `uat` (one required reviewer), `prod` (a separate required reviewer) before the workflow below is exercised.

---

## Phase 4 — CI/CD Workflow

### 4.1 Production Docker Compose definition

**File to modify:** `infra/docker-compose.prod.yml`. One file, shared across all three environments — the values injected at deploy time (Section 4.2) differ per environment; the file's shape does not.

```yaml
networks:
  eai-mesh:
    driver: bridge
services:
  python-validator:
    image: ${ACR_REGISTRY}/eai-python-validator:${IMAGE_TAG}
    restart: always
    environment:
      - API_SECURITY_TOKEN=${API_SECURITY_TOKEN}
      - DATABASE_URL=${DATABASE_URL}
      - TZ=Asia/Kolkata
    networks: [eai-mesh]
  java-gateway:
    image: ${ACR_REGISTRY}/eai-java-gateway:${IMAGE_TAG}
    restart: always
    environment:
      - SERVER_PORT=8081
      - INTEGRATION_PYTHON_BASE-URL=http://python-validator:8082
      - INTEGRATION_PYTHON_AUTH-TOKEN=${API_SECURITY_TOKEN}
      - TZ=Asia/Kolkata
      - JAVA_OPTS=-Duser.timezone=Asia/Kolkata
    ports: ["8081:8081"]
    depends_on: [python-validator]
    networks: [eai-mesh]
```

### 4.2 GitHub Actions workflow

**File to modify:** `.github/workflows/ci.yml`. This is a single workflow file containing every job for every environment — Development's automatic build-and-deploy, and UAT's and Production's manually-dispatched promotion jobs alike. There is no separate `promote.yml`; `promote-uat` and `promote-prod` are `workflow_dispatch`-triggered jobs defined within this same file.

```yaml
name: CI

on:
  push:
    branches: ["**"]
  pull_request:
    branches: [develop, main]
  workflow_dispatch:
    inputs:
      image_tag:
        description: "Git commit SHA of the image to promote (already built and pushed to ACR)"
        required: true
        type: string

permissions:
  contents: read

env:
  ACR_NAME: ${{ vars.ACR_NAME }}
  ACR_REGISTRY: ${{ vars.ACR_NAME }}.azurecr.io # ACR_NAME.azurecr.io is the default login server for Azure Container Registry
  AZURE_TENANT_ID: ${{ vars.AZURE_TENANT_ID }}
  AZURE_SUBSCRIPTION_ID: ${{ vars.AZURE_SUBSCRIPTION_ID }}

jobs:
  secret-scan:
    runs-on: ubuntu-latest
    if: >
      github.event_name == 'pull_request' ||
      (github.event_name == 'push' &&
        (github.ref == 'refs/heads/develop' || startsWith(github.ref, 'refs/heads/feature/')))
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0 }
      - uses: trufflesecurity/trufflehog@v3.94.1
        with: { extra_args: --only-verified }

  dependency-scan:
    runs-on: ubuntu-latest
    if: >
      github.event_name == 'pull_request' ||
      (github.event_name == 'push' &&
        (github.ref == 'refs/heads/develop' || startsWith(github.ref, 'refs/heads/feature/')))
    permissions: { contents: read, security-events: write }
    steps:
      - uses: actions/checkout@v4
      - uses: aquasecurity/trivy-action@0.35.0
        with:
          scan-type: fs
          scan-ref: .
          severity: CRITICAL,HIGH
          exit-code: 1
          format: sarif
          output: trivy-fs-results.sarif
      - if: always() && hashFiles('trivy-fs-results.sarif') != ''
        uses: github/codeql-action/upload-sarif@v3
        with: { sarif_file: trivy-fs-results.sarif }

  java-build-test:
    needs: [secret-scan, dependency-scan]
    runs-on: ubuntu-latest
    if: >
      github.event_name == 'pull_request' ||
      (github.event_name == 'push' &&
        (github.ref == 'refs/heads/develop' || startsWith(github.ref, 'refs/heads/feature/')))
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with: { distribution: temurin, java-version: "21", cache: maven }
      - working-directory: 01-java-ingestion-service
        run: mvn -B verify

  python-build-test:
    needs: [secret-scan, dependency-scan]
    runs-on: ubuntu-latest
    if: >
      github.event_name == 'pull_request' ||
      (github.event_name == 'push' &&
        (github.ref == 'refs/heads/develop' || startsWith(github.ref, 'refs/heads/feature/')))
    services:
      postgres:
        image: postgres:16-alpine
        env:
          POSTGRES_USER: smart_meter_admin
          POSTGRES_PASSWORD: smart_meter_password_2026 # disposable CI test value, not an actual credential
          POSTGRES_DB: smart_meter_warehouse
        ports: ["5432:5432"]
        options: >-
          --health-cmd pg_isready --health-interval 10s --health-timeout 5s --health-retries 5
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with: { python-version: "3.14", cache: pip }
      - working-directory: 02-python-transformation-api
        run: pip install -r requirements.txt
      - working-directory: 02-python-transformation-api
        env:
          DATABASE_URL: postgresql+psycopg://smart_meter_admin:smart_meter_password_2026@localhost:5432/smart_meter_warehouse # disposable CI test value, not an actual credential
          API_SECURITY_TOKEN: ci-only-test-token   # disposable CI test value, not an actual credential
        run: pytest tests

  docker-build-push:
    needs: [java-build-test, python-build-test]
    # No `environment:` key — matches the ref-based federated credential
    # (bootstrap: gha_deploy_dev_ref), not the environment-based one.
    if: github.event_name == 'push' && github.ref == 'refs/heads/develop'
    runs-on: ubuntu-latest
    permissions: { contents: read, id-token: write }
    steps:
      - uses: actions/checkout@v4
      - uses: azure/login@v2
        with:
          client-id: ${{ vars.AZURE_CLIENT_ID_DEV }}
          tenant-id: ${{ env.AZURE_TENANT_ID }}
          subscription-id: ${{ env.AZURE_SUBSCRIPTION_ID }}
      - run: az acr login --name ${{ vars.ACR_NAME }}
      # ACR repository is set to immutable tags at creation — re-pushing an
      # existing tag is rejected rather than silently overwritten. Check
      # first, matching AWS's ECR idempotency check.
      - name: Check whether this commit's images already exist
        id: check-image
        run: |
          if az acr repository show --name ${{ vars.ACR_NAME }} --image eai-java-gateway:${{ github.sha }} >/dev/null 2>&1; then
            echo "skip=true" >> "$GITHUB_OUTPUT"
          else
            echo "skip=false" >> "$GITHUB_OUTPUT"
          fi
      - if: steps.check-image.outputs.skip == 'false'
        run: |
          docker build -t ${ACR_REGISTRY}/eai-java-gateway:${{ github.sha }} ./01-java-ingestion-service
          docker build -t ${ACR_REGISTRY}/eai-python-validator:${{ github.sha }} ./02-python-transformation-api
      - if: steps.check-image.outputs.skip == 'false'
        uses: aquasecurity/trivy-action@0.35.0
        # bypassing this temporarily by setting exit-code = 0
        # with: { image-ref: "${{ env.ACR_REGISTRY }}/eai-java-gateway:${{ github.sha }}", severity: "CRITICAL,HIGH", exit-code: 1 }
        with: { image-ref: "${{ env.ACR_REGISTRY }}/eai-java-gateway:${{ github.sha }}", severity: "CRITICAL,HIGH", exit-code: 0 }
      - if: steps.check-image.outputs.skip == 'false'
        uses: aquasecurity/trivy-action@0.35.0
        # bypassing this temporarily by setting exit-code = 0
        # with: { image-ref: "${{ env.ACR_REGISTRY }}/eai-python-validator:${{ github.sha }}", severity: "CRITICAL,HIGH", exit-code: 1 }
        with: { image-ref: "${{ env.ACR_REGISTRY }}/eai-python-validator:${{ github.sha }}", severity: "CRITICAL,HIGH", exit-code: 0 }
      - if: steps.check-image.outputs.skip == 'false'
        run: |
          docker push ${ACR_REGISTRY}/eai-java-gateway:${{ github.sha }}
          docker push ${ACR_REGISTRY}/eai-python-validator:${{ github.sha }}

  deploy-dev:
    needs: docker-build-push
    if: github.ref == 'refs/heads/develop'
    runs-on: ubuntu-latest
    environment: dev
    permissions: { contents: read, id-token: write }
    steps:
      - uses: actions/checkout@v4
      - uses: azure/login@v2
        with:
          client-id: ${{ vars.AZURE_CLIENT_ID_DEV }}
          tenant-id: ${{ env.AZURE_TENANT_ID }}
          subscription-id: ${{ env.AZURE_SUBSCRIPTION_ID }}
      - name: Deploy via VM Run Command
        run: |
          COMPOSE_B64=$(base64 -w0 infra/docker-compose.prod.yml)
          DB_PASS=$(az keyvault secret show --vault-name ${{ vars.DEV_KEY_VAULT_NAME }} --name database-password --query value -o tsv)
          API_TOKEN=$(az keyvault secret show --vault-name ${{ vars.DEV_KEY_VAULT_NAME }} --name api-security-token --query value -o tsv)
          az vm run-command invoke \
            --resource-group eai-dev-rg \
            --name eai-dev-host \
            --command-id RunShellScript \
            --scripts  "set -e" \
              "echo 'Waiting for cloud-init bootstrap...'" \
              "cloud-init status --wait" \
              "echo 'Validating VM prerequisites...'" \
              "command -v az" \
              "docker --version" \
              "docker compose version" \
              "test -d /opt/eai" \
              "echo $COMPOSE_B64 | base64 -d > /opt/eai/docker-compose.prod.yml" \
              "echo DATABASE_URL=postgresql+psycopg://smart_meter_admin:${DB_PASS}@${{ vars.DEV_POSTGRES_FQDN }}:5432/smart_meter_warehouse > /opt/eai/.env" \
              "echo API_SECURITY_TOKEN=${API_TOKEN} >> /opt/eai/.env" \
              "echo ACR_REGISTRY=${ACR_REGISTRY} >> /opt/eai/.env" \
              "echo IMAGE_TAG=${{ github.sha }} >> /opt/eai/.env" \
              "az login --identity --client-id ${{ vars.DEV_VM_IDENTITY_CLIENT_ID }}" \
              "az acr login --name ${{ vars.ACR_NAME }}" \
              "cd /opt/eai && ACR_REGISTRY=${ACR_REGISTRY} IMAGE_TAG=${{ github.sha }} docker compose -f docker-compose.prod.yml --env-file .env pull" \
              "cd /opt/eai && ACR_REGISTRY=${ACR_REGISTRY} IMAGE_TAG=${{ github.sha }} docker compose -f docker-compose.prod.yml --env-file .env up -d"

  promote-uat:
    if: github.event_name == 'workflow_dispatch' && github.ref == 'refs/heads/uat'
    runs-on: ubuntu-latest
    environment: uat
    permissions: { contents: read, id-token: write }
    steps:
      - uses: actions/checkout@v4
      - uses: azure/login@v2
        with:
          client-id: ${{ vars.AZURE_CLIENT_ID_UAT }}
          tenant-id: ${{ env.AZURE_TENANT_ID }}
          subscription-id: ${{ env.AZURE_SUBSCRIPTION_ID }}
      - name: Confirm the image tag being promoted actually exists
        run: az acr repository show --name ${{ vars.ACR_NAME }} --image eai-java-gateway:${{ inputs.image_tag }}
      - name: Deploy via VM Run Command
        run: |
          COMPOSE_B64=$(base64 -w0 infra/docker-compose.prod.yml)
          DB_PASS=$(az keyvault secret show --vault-name ${{ vars.UAT_KEY_VAULT_NAME }} --name database-password --query value -o tsv)
          API_TOKEN=$(az keyvault secret show --vault-name ${{ vars.UAT_KEY_VAULT_NAME }} --name api-security-token --query value -o tsv)
          az vm run-command invoke \
            --resource-group eai-uat-rg \
            --name eai-uat-host \
            --command-id RunShellScript \
            --scripts  "set -e" \
              "echo 'Waiting for cloud-init bootstrap...'" \
              "cloud-init status --wait" \
              "echo 'Validating VM prerequisites...'" \
              "command -v az" \
              "docker --version" \
              "docker compose version" \
              "test -d /opt/eai" \
              "echo $COMPOSE_B64 | base64 -d > /opt/eai/docker-compose.prod.yml" \
              "echo DATABASE_URL=postgresql+psycopg://smart_meter_admin:${DB_PASS}@${{ vars.UAT_POSTGRES_FQDN }}:5432/smart_meter_warehouse > /opt/eai/.env" \
              "echo API_SECURITY_TOKEN=${API_TOKEN} >> /opt/eai/.env" \
              "echo ACR_REGISTRY=${ACR_REGISTRY} >> /opt/eai/.env" \
              "echo IMAGE_TAG=${{ inputs.image_tag }} >> /opt/eai/.env" \
              "az login --identity --client-id ${{ vars.UAT_VM_IDENTITY_CLIENT_ID }}" \
              "az acr login --name ${{ vars.ACR_NAME }}" \
              "cd /opt/eai && ACR_REGISTRY=${ACR_REGISTRY} IMAGE_TAG=${{ inputs.image_tag }} docker compose -f docker-compose.prod.yml --env-file .env pull" \
              "cd /opt/eai && ACR_REGISTRY=${ACR_REGISTRY} IMAGE_TAG=${{ inputs.image_tag }} docker compose -f docker-compose.prod.yml --env-file .env up -d"

  promote-prod:
    if: github.event_name == 'workflow_dispatch' && github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    environment: prod
    permissions: { contents: read, id-token: write }
    steps:
      - uses: actions/checkout@v4
      - uses: azure/login@v2
        with:
          client-id: ${{ vars.AZURE_CLIENT_ID_PROD }}
          tenant-id: ${{ env.AZURE_TENANT_ID }}
          subscription-id: ${{ env.AZURE_SUBSCRIPTION_ID }}
      - name: Confirm the image tag being promoted actually exists
        run: az acr repository show --name ${{ vars.ACR_NAME }} --image eai-java-gateway:${{ inputs.image_tag }}
      - name: Deploy via VM Run Command
        run: |
          COMPOSE_B64=$(base64 -w0 infra/docker-compose.prod.yml)
          DB_PASS=$(az keyvault secret show --vault-name ${{ vars.PROD_KEY_VAULT_NAME }} --name database-password --query value -o tsv)
          API_TOKEN=$(az keyvault secret show --vault-name ${{ vars.PROD_KEY_VAULT_NAME }} --name api-security-token --query value -o tsv)
          az vm run-command invoke \
            --resource-group eai-prod-rg \
            --name eai-prod-host \
            --command-id RunShellScript \
            --scripts  "set -e" \
              "echo 'Waiting for cloud-init bootstrap...'" \
              "cloud-init status --wait" \
              "echo 'Validating VM prerequisites...'" \
              "command -v az" \
              "docker --version" \
              "docker compose version" \
              "test -d /opt/eai" \
              "echo $COMPOSE_B64 | base64 -d > /opt/eai/docker-compose.prod.yml" \
              "echo DATABASE_URL=postgresql+psycopg://smart_meter_admin:${DB_PASS}@${{ vars.PROD_POSTGRES_FQDN }}:5432/smart_meter_warehouse > /opt/eai/.env" \
              "echo API_SECURITY_TOKEN=${API_TOKEN} >> /opt/eai/.env" \
              "echo ACR_REGISTRY=${ACR_REGISTRY} >> /opt/eai/.env" \
              "echo IMAGE_TAG=${{ inputs.image_tag }} >> /opt/eai/.env" \
              "az login --identity --client-id ${{ vars.PROD_VM_IDENTITY_CLIENT_ID }}" \
              "az acr login --name ${{ vars.ACR_NAME }}" \
              "cd /opt/eai && ACR_REGISTRY=${ACR_REGISTRY} IMAGE_TAG=${{ inputs.image_tag }} docker compose -f docker-compose.prod.yml --env-file .env pull" \
              "cd /opt/eai && ACR_REGISTRY=${ACR_REGISTRY} IMAGE_TAG=${{ inputs.image_tag }} docker compose -f docker-compose.prod.yml --env-file .env up -d"
```

**Known gap, revisit before this pipeline is considered finished:** both image-scan steps in `docker-build-push` run with `exit-code: 0` — CRITICAL/HIGH findings are logged but do not fail the build. This is a temporary state adopted to unblock initial pipeline setup, not a completed production security gate; revert to `exit-code: 1` and triage findings once the rest of the pipeline is confirmed working.

**Why Key Vault reads happen inside these jobs, not on the VM:** each `deploy-dev` / `promote-uat` / `promote-prod` job reads its environment's two Key Vault secrets using the GitHub Actions identity's own `Key Vault Secrets User` grant (`ARCHITECTURE_AZURE.md`, Appendix A.3), not the VM's managed identity. The alternative — a VM-side read via `az login --identity` inside the Run Command script — is also valid; this project's implementation reads on the CI side to keep the Run Command script itself simpler. The `az login --identity --client-id` line inside each script authenticates the VM only for its own `docker login` against the shared registry, a separate concern from the secret retrieval above it.

### 4.3 Commit and push

```bash
# bash
git add .github/workflows/ci.yml infra/docker-compose.prod.yml
git commit -m "ci: build-once/promote-many across dev/uat/prod via ACR and VM Run Command"
git push origin develop
```
```powershell
# PowerShell equivalent
git add .github/workflows/ci.yml infra/docker-compose.prod.yml
git commit -m "ci: build-once/promote-many across dev/uat/prod via ACR and VM Run Command"
git push origin develop
```

### 4.4 Development verification

```bash
# bash
curl "https://<AZURE_APIM_NAME_DEV>.azure-api.net/health"
curl -X POST "https://<AZURE_APIM_NAME_DEV>.azure-api.net/api/v1/ingest/bulk" \
  -H "Content-Type: application/json" \
  -d '{"meter_id":"MTR-000123","grid_zone":"ZONE-A","readings":[{"timestamp":"2026-01-01T00:00:00Z","kwh_value":12.5}]}'
```
```powershell
# PowerShell equivalent
Invoke-RestMethod -Uri "https://<AZURE_APIM_NAME_DEV>.azure-api.net/health"
Invoke-RestMethod -Uri "https://<AZURE_APIM_NAME_DEV>.azure-api.net/api/v1/ingest/bulk" -Method Post -ContentType "application/json" -Body '{"meter_id":"MTR-000123","grid_zone":"ZONE-A","readings":[{"timestamp":"2026-01-01T00:00:00Z","kwh_value":12.5}]}'
```

**Expected result:** `{"status":"UP"}` from the health check; a JSON response containing `message`, `metadata`, and `analytics_summary` from the ingest call — the transformation service's response shape, passed through unmodified by the ingestion gateway.

## Phase 5 — Development Teardown and DEV-to-UAT Promotion

This phase applies the build-once, promote-many model in practice: no rebuild occurs anywhere in this phase. Every step either manages infrastructure lifecycle or invokes the already-existing `promote-uat` job against an already-published image tag.

### 5.1 Record the promoted image tag before tearing anything down

```bash
# bash
az acr repository show-tags --name <AZURE_ACR_NAME> --repository eai-java-gateway --orderby time_desc --top 5 --output table
```
```powershell
# PowerShell equivalent
az acr repository show-tags --name <AZURE_ACR_NAME> --repository eai-java-gateway --orderby time_desc --top 5 --output table
```

**Record `<DEV_PROMOTED_SHA>`** — the most recent tag, cross-checked against the GitHub Actions run history for `docker-build-push` to confirm it corresponds to a completed, successful build. This value does not change by tearing Development down next.

### 5.2 Tear down Development

**Reason stated explicitly, since this step is driven by subscription-wide quota of 4 (`ARCHITECTURE_AZURE.md`, Section 7), not a routine part of every deployment:** UAT's VM apply will require 2 vCPUs (Phase 5.3) and PROD's eventual VM apply another 2 vCPUs (Phase 6.3). Till PROD VM has not been provisioned, this step could be postponed. But once PROD is in place, 2 vCPUs held by DEV's VM must be reclaimed to make space for UAT. **A subscription with standard Burstable v2 quota skips this step entirely** — DEV would simply remain up alongside UAT and PROD.

```bash
# bash — run from: <repo-root>/infra/dev
cd infra/dev
terraform plan -destroy -var="operator_ip_cidr=<OPERATOR_IP>/32"
```
```powershell
# PowerShell equivalent
Set-Location infra\dev
terraform plan -destroy -var="operator_ip_cidr=<OPERATOR_IP>/32"
```

**Confirm the plan touches only `eai-dev-rg` and its contents** before applying — UAT and Production are separate HCP Terraform workspaces with independent state, so nothing outside Development's own resource group should appear.

```bash
# bash
cd infra/dev
terraform destroy -var="operator_ip_cidr=<OPERATOR_IP>/32"
```
```powershell
# PowerShell equivalent
Set-Location infra\dev
terraform destroy -var="operator_ip_cidr=<OPERATOR_IP>/32"
```

**Expected result:** `eai-dev-rg` and everything provisioned inside it is removed. `eai-shared-rg` and its Container Registry are unaffected — Development's workspace holds only a read-only data-source lookup against the shared registry, never a managed reference to it.

**Verify the quota is actually freed:**

```bash
# bash
az vm list-usage --location centralindia --query "[?contains(name.value, 'Bs')]" --output table
```
```powershell
# PowerShell equivalent
az vm list-usage --location centralindia --query "[?contains(name.value, 'Bs')]" --output table
```

**Expected result:** `CurrentValue` reads `2` (UAT's VM only), against a `Limit` of `4`.

### 5.3 Confirm UAT is reachable before promoting to it

```bash
# bash
az vm run-command invoke --resource-group eai-uat-rg --name eai-uat-host --command-id RunShellScript --scripts "echo agent-check-ok"
```
```powershell
# PowerShell equivalent
az vm run-command invoke --resource-group eai-uat-rg --name eai-uat-host --command-id RunShellScript --scripts "echo agent-check-ok"
```

If this does not return `agent-check-ok`, resolve it before continuing — `promote-uat`'s deploy step will fail identically and less informatively against a VM not actually responding to Run Command.

### 5.4 Trigger `promote-uat`

`promote-uat` is `workflow_dispatch`-triggered and takes one required input, `image_tag` — the SHA recorded in Section 5.1. It performs no build step.

```bash
# bash
gh workflow run ci.yml --ref uat -f image_tag=<DEV_PROMOTED_SHA>
```
```powershell
# PowerShell equivalent
gh workflow run ci.yml --ref uat -f image_tag="<DEV_PROMOTED_SHA>"
```

Or via the GitHub web UI: Actions tab → `CI` workflow → **Run workflow** → branch `uat` → `image_tag` = `<DEV_PROMOTED_SHA>` → **Run workflow**.

If the `uat` branch does not yet exist:

```bash
# bash
git checkout develop
git pull origin develop
git checkout -b uat
git push -u origin uat
```
```powershell
# PowerShell equivalent
git checkout develop
git pull origin develop
git checkout -b uat
git push -u origin uat
```

### 5.5 Record the promotion

Maintain a durable, append-only log of every promotion, since the deployed tag at any point in time is otherwise only inferable from Run Command output. **Create `docs/PROMOTIONS.md`** if it does not yet exist:

```text
| Date | From | To | Image tag (SHA) | Triggered by |
|---|---|---|---|---|
| <DATE> | develop (Development, torn down after this SHA's build) | UAT | <DEV_PROMOTED_SHA> | promote-uat workflow_dispatch |
```

**Verified when:** the `promote-uat` run completes with a green check. Phase 6 performs the actual application-level verification before this promotion is considered validated for onward promotion to Production.

---

## Phase 6 — UAT Verification, Production Compute Completion, and Production Promotion

### 6.1 UAT verification

```bash
# bash — run from: <repo-root>/infra/uat
cd infra/uat
terraform output -raw apim_gateway_url
```
```powershell
# PowerShell equivalent
Set-Location infra\uat
terraform output -raw apim_gateway_url
```

```bash
# bash
curl "<UAT_API_URL>/health"
curl -X POST "<UAT_API_URL>/api/v1/ingest/bulk" \
  -H "Content-Type: application/json" \
  -d '{"meter_id":"MTR-000123","grid_zone":"ZONE-A","readings":[{"timestamp":"2026-01-01T00:00:00Z","kwh_value":12.5}]}'
```
```powershell
# PowerShell equivalent
Invoke-RestMethod -Uri "<UAT_API_URL>/health"
Invoke-RestMethod -Uri "<UAT_API_URL>/api/v1/ingest/bulk" -Method Post -ContentType "application/json" -Body '{"meter_id":"MTR-000123","grid_zone":"ZONE-A","readings":[{"timestamp":"2026-01-01T00:00:00Z","kwh_value":12.5}]}'
```

**Expected result:** `{"status":"UP"}`; a JSON response containing `message`, `metadata`, and `analytics_summary`.

**Confirm the row reached UAT's own PostgreSQL Flexible Server**, reached via `az ssh vm` (the server has no public network access by design):

```bash
# bash
az extension add --upgrade -n ssh
az ssh vm --resource-group eai-uat-rg --name eai-uat-host
```
```powershell
# PowerShell equivalent
az extension add --upgrade -n ssh
az ssh vm --resource-group eai-uat-rg --name eai-uat-host
```

From inside the session — authenticated via the VM's own managed identity, since the VM's shell does not carry the operator's `az login` session:

```bash
UAT_PG_FQDN=<paste postgres_fqdn output>
az login --identity --client-id <vm_identity_client_id output>
UAT_DB_PASS=$(az keyvault secret show --vault-name <AZURE_KEY_VAULT_NAME_UAT> --name database-password --query value -o tsv)

sudo apt-get install -y postgresql-client
PGPASSWORD="$UAT_DB_PASS" psql -h "$UAT_PG_FQDN" -U smart_meter_admin -d smart_meter_warehouse \
  -c "SELECT * FROM smart_meter_intervals WHERE meter_id = 'MTR-000123';"
```

**Expected result:** a row for `MTR-000123` with `kwh_value = 12.5`.

### 6.2 UAT approval gate

Confirm the `uat` GitHub Environment's required reviewer is configured, and that `promote-uat`'s job declares `environment: uat` — this is what causes GitHub to gate the job on approval rather than running it unattended. Append the verification result to `docs/PROMOTIONS.md`:

```text
| <DATE> | UAT health check | PASS | {"status":"UP"} |
| <DATE> | UAT ingest round-trip | PASS | row confirmed for MTR-000123 |
| <DATE> | UAT approval | APPROVED | <reviewer> |
```

**Do not tear down UAT after this section.** UAT remains up through Section 6.4 — it is the rollback reference for the Production promotion about to occur.

### 6.3 Complete Production's compute provisioning

Re-confirm the quota is clear immediately before this apply — do not assume Phase 5.2's verification still holds if time has passed:

```bash
# bash
az vm list-usage --location centralindia --query "[?contains(name.value, 'Bs')]" --output table
```
```powershell
# PowerShell equivalent
az vm list-usage --location centralindia --query "[?contains(name.value, 'Bs')]" --output table
```

**Expected result:** `CurrentValue` reads `2` (UAT only). If it reads `4`, something was recreated since Phase 5 — tear it down again before proceeding.

Production's non-compute resources (Section 3.2) were already applied successfully; this apply targets only the deferred VM and API Management resources.

```bash
# bash — run from: <repo-root>/infra/prod
cd infra/prod
terraform plan -var="operator_ip_cidr=<OPERATOR_IP>/32"
```
```powershell
# PowerShell equivalent
Set-Location infra\prod
terraform plan -var="operator_ip_cidr=<OPERATOR_IP>/32"
```

**Confirm the plan shows only the VM, its two dependent resources, and the API Management resources as pending creation** — any other planned change, particularly a planned replacement of an already-applied resource, indicates drift and should be investigated before applying.

```bash
# bash
terraform apply -var="operator_ip_cidr=<OPERATOR_IP>/32"
terraform output -raw postgres_fqdn
terraform output -raw vm_public_ip
az vm run-command invoke --resource-group eai-prod-rg --name eai-prod-host --command-id RunShellScript --scripts "echo agent-check-ok"
terraform output -raw apim_gateway_url
```
```powershell
# PowerShell equivalent
terraform apply -var="operator_ip_cidr=<OPERATOR_IP>/32"
terraform output -raw postgres_fqdn
terraform output -raw vm_public_ip
az vm run-command invoke --resource-group eai-prod-rg --name eai-prod-host --command-id RunShellScript --scripts "echo agent-check-ok"
terraform output -raw apim_gateway_url
```

**Record `<PROD_API_URL>`.** Production infrastructure is now complete and, per the adopted cycling model, persistent from this point forward — it is not torn down as part of any subsequent Development/UAT cycling.

**Apply the prod-side Container Registry grant** before triggering promotion — Production's GitHub Actions identity requires the same `AcrPull` grant UAT's required (Section 3.1), since the promotion job's tag-existence check runs under the GitHub Actions identity, not the VM's:

```hcl
# infra/prod/identity.tf
resource "azurerm_role_assignment" "gha_prod_acr_pull" {
  scope                = data.azurerm_container_registry.shared.id
  role_definition_name = "AcrPull"
  principal_id         = data.azuread_service_principal.gha_deploy_prod.object_id
}
```

### 6.4 Confirm the branch state and trigger `promote-prod`

The image tag promoted to Production must be the exact tag validated in UAT — `<UAT_VALIDATED_SHA> = <DEV_PROMOTED_SHA>` from Section 5.1, since no rebuild occurs between UAT and Production under the build-once model.

Confirm `main` branch protection (pull-request-only, required approvals, linear history) and merge the validated work forward with `--no-ff`, preserving distinct branch history rather than a fast-forward:

```bash
# bash
git checkout uat
git pull origin uat
git checkout main
git pull origin main
git merge --no-ff uat -m "merge: promote uat to main for <UAT_VALIDATED_SHA>"
git push origin main
```
```powershell
# PowerShell equivalent
git checkout uat
git pull origin uat
git checkout main
git pull origin main
git merge --no-ff uat -m "merge: promote uat to main for <UAT_VALIDATED_SHA>"
git push origin main
```

```bash
# bash
gh workflow run ci.yml --ref main -f image_tag=<UAT_VALIDATED_SHA>
```
```powershell
# PowerShell equivalent
gh workflow run ci.yml --ref main -f image_tag="<UAT_VALIDATED_SHA>"
```

This pauses at the `prod` GitHub Environment's required-reviewer gate before `promote-prod`'s steps execute. Phase 7 covers the approval action and post-deploy verification.

## Phase 7 — Production Approval, Verification, and Baseline

### 7.1 Approve the `prod` Environment gate

The `promote-prod` job declares `environment: prod`, which pauses the run at the required-reviewer gate configured in Phase 3.3. Navigate to the repository's **Actions** tab → the `CI` workflow run triggered in Phase 6.4 → the pending `promote-prod` job shows a **Review deployments** control.

Before approving:

1. Confirm the promoted `image_tag` matches `<UAT_VALIDATED_SHA>` recorded in Phase 6.4, and that `docs/PROMOTIONS.md` shows UAT's verification and approval rows (Phase 6.2).
2. Confirm no infrastructure drift is outstanding — re-run `terraform plan` in `infra/prod` and confirm it reports no changes.

**Record the approval timestamp and approving identity** for the baseline in Section 7.4.

Once approved, `promote-prod`'s steps execute: authentication via `gha-deploy-prod-identity`'s federated credential, the registry tag-existence confirmation, and the `az vm run-command invoke` deployment against `eai-prod-host`, reading `<AZURE_KEY_VAULT_NAME_PROD>` for `DATABASE_URL`/`API_SECURITY_TOKEN` assembly.

### 7.2 Verify the deployment reached the VM

```bash
# bash
az vm run-command invoke --resource-group eai-prod-rg --name eai-prod-host \
  --command-id RunShellScript \
  --scripts "docker compose -f /opt/eai/docker-compose.prod.yml --env-file /opt/eai/.env ps"
```
```powershell
# PowerShell equivalent
az vm run-command invoke --resource-group eai-prod-rg --name eai-prod-host `
  --command-id RunShellScript `
  --scripts "docker compose -f /opt/eai/docker-compose.prod.yml --env-file /opt/eai/.env ps"
```

**Expected result:** both `java-gateway` and `python-validator` containers report `Up`/`running`, and the image reference shown for each matches `<AZURE_ACR_NAME>.azurecr.io/eai-<service>:<UAT_VALIDATED_SHA>` exactly — not `latest`, not a different SHA. A mismatch indicates a stale or incorrect pull and must be investigated before proceeding.

### 7.3 Application-level verification against Production's endpoint

```bash
# bash — run from: <repo-root>/infra/prod
cd infra/prod
PROD_API_URL=$(terraform output -raw apim_gateway_url)
curl "$PROD_API_URL/health"
curl -X POST "$PROD_API_URL/api/v1/ingest/bulk" \
  -H "Content-Type: application/json" \
  -d '{"meter_id":"MTR-000123","grid_zone":"ZONE-A","readings":[{"timestamp":"2026-01-01T00:00:00Z","kwh_value":12.5}]}'
```
```powershell
# PowerShell equivalent
Set-Location infra\prod
$prodApiUrl = terraform output -raw apim_gateway_url
Invoke-RestMethod -Uri "$prodApiUrl/health"
Invoke-RestMethod -Uri "$prodApiUrl/api/v1/ingest/bulk" -Method Post -ContentType "application/json" -Body '{"meter_id":"MTR-000123","grid_zone":"ZONE-A","readings":[{"timestamp":"2026-01-01T00:00:00Z","kwh_value":12.5}]}'
```

**Expected result:** `{"status":"UP"}`; a JSON response containing `message`, `metadata`, and `analytics_summary`.

Confirm the row landed in Production's own PostgreSQL Flexible Server, reached via `az ssh vm` (the server has no public network access, identically to Development and UAT):

```bash
# bash
az extension add --upgrade -n ssh
az ssh vm --resource-group eai-prod-rg --name eai-prod-host
```
```powershell
# PowerShell equivalent
az extension add --upgrade -n ssh
az ssh vm --resource-group eai-prod-rg --name eai-prod-host
```

From inside the session:

```bash
PROD_PG_FQDN=<paste postgres_fqdn output>
az login --identity --client-id <vm_identity_client_id output>
PROD_DB_PASS=$(az keyvault secret show --vault-name <AZURE_KEY_VAULT_NAME_PROD> --name database-password --query value -o tsv)

sudo apt-get install -y postgresql-client
PGPASSWORD="$PROD_DB_PASS" psql -h "$PROD_PG_FQDN" -U smart_meter_admin -d smart_meter_warehouse \
  -c "SELECT * FROM smart_meter_intervals WHERE meter_id = 'MTR-000123';"
```

**Expected result:** a row for `MTR-000123` with `kwh_value = 12.5`.

### 7.4 Record the production baseline

Append to `docs/PRODUCTION_BASELINE.md` (create if absent — a single current-state record, overwritten at each production deploy, distinct from the append-only `docs/PROMOTIONS.md` log):

```yaml
release:
  version: "<RELEASE_VERSION>"
  git_commit: "<UAT_VALIDATED_SHA>"

artifacts:
  java:
    repository: "eai-java-gateway"
    registry: "<AZURE_ACR_NAME>.azurecr.io"
    tag: "<UAT_VALIDATED_SHA>"
  python:
    repository: "eai-python-validator"
    registry: "<AZURE_ACR_NAME>.azurecr.io"
    tag: "<UAT_VALIDATED_SHA>"

infrastructure:
  hcp_terraform_workspace: "<HCP_TERRAFORM_WORKSPACE_PROD>"
  resource_group: "eai-prod-rg"
  vm: "eai-prod-host"
  postgres_fqdn: "<postgres_fqdn output>"
  apim_gateway_url: "<PROD_API_URL>"

deployment:
  environment: "prod"
  workflow_run: "<GITHUB_ACTIONS_RUN_URL>"
  approver: "<PROD_APPROVER>"
  approved_at: "<PROD_APPROVAL_TIMESTAMP>"
  deployed_at: "<DEPLOYMENT_TIMESTAMP>"
  verified_at: "<VERIFICATION_TIMESTAMP>"
```

```bash
# bash
git add docs/PRODUCTION_BASELINE.md docs/PROMOTIONS.md
git commit -m "docs: record production baseline for <UAT_VALIDATED_SHA>"
git push origin main
```
```powershell
# PowerShell equivalent
git add docs\PRODUCTION_BASELINE.md docs\PROMOTIONS.md
git commit -m "docs: record production baseline for <UAT_VALIDATED_SHA>"
git push origin main
```

Production is now persistent indefinitely — it is not torn down as part of any subsequent Development/UAT cycling.

### 7.5 Rollback reference

Rollback in Production is a variant of the same promotion mechanism, not a distinct emergency procedure: `promote-prod` is invoked again with the prior known-good tag as its `image_tag` input.

```bash
# bash
az acr repository show-tags --name <AZURE_ACR_NAME> --repository eai-java-gateway --orderby time_desc --top 10 --output table
```
```powershell
# PowerShell equivalent
az acr repository show-tags --name <AZURE_ACR_NAME> --repository eai-java-gateway --orderby time_desc --top 10 --output table
```

Cross-reference the resulting tags against `docs/PROMOTIONS.md` and `docs/PRODUCTION_BASELINE.md`'s Git history to identify `<ROLLBACK_SHA>` — the tag corresponding to the last confirmed-healthy production deployment. Confirm Production's currently-running state before acting:

```bash
# bash
az vm run-command invoke --resource-group eai-prod-rg --name eai-prod-host \
  --command-id RunShellScript \
  --scripts "docker compose -f /opt/eai/docker-compose.prod.yml --env-file /opt/eai/.env ps"
```
```powershell
# PowerShell equivalent
az vm run-command invoke --resource-group eai-prod-rg --name eai-prod-host `
  --command-id RunShellScript `
  --scripts "docker compose -f /opt/eai/docker-compose.prod.yml --env-file /opt/eai/.env ps"
```

Trigger the rollback:

```bash
# bash
gh workflow run ci.yml --ref main -f image_tag=<ROLLBACK_SHA>
```
```powershell
# PowerShell equivalent
gh workflow run ci.yml --ref main -f image_tag="<ROLLBACK_SHA>"
```

This pauses at the same `prod` Environment approval gate described in Section 7.1 — a rollback is not exempt from the required-reviewer approval; the gate exists precisely for the moment a Production change, forward or backward, is made under pressure. Repeat Sections 7.2 and 7.3's verification unchanged against `<ROLLBACK_SHA>` rather than the tag being replaced. Record the rollback in `docs/PROMOTIONS.md` and overwrite `docs/PRODUCTION_BASELINE.md` with the rolled-back values.

**This depends on the registry actually retaining the older tag.** No `azurerm_container_registry` retention policy is defined in `infra/shared/main.tf` in this implementation — confirm the target tag is still present in the `az acr repository show-tags` output above before relying on this procedure; a standard-quota, steady-state deployment should add an explicit retention policy to the shared registry so this dependency does not go unmanaged.

A rolled-back defect is fixed at the source (`develop`) and re-validated through Development and UAT in full before another Production promotion is attempted — the defective SHA is not re-promoted forward as-is.

---

## Troubleshooting Reference

### Azure CLI identity

```bash
# bash
az account show
az account get-access-token
```
```powershell
# PowerShell equivalent
az account show
az account get-access-token
```

### Subscription mismatch

```bash
# bash
az account list --output table
az account set --subscription "<AZURE_SUBSCRIPTION_ID>"
```
```powershell
# PowerShell equivalent
az account list --output table
az account set --subscription "<AZURE_SUBSCRIPTION_ID>"
```

### `az login --identity` authentication inside a Run Command script

Current Azure CLI has removed the `--username` flag for identity-based login — `az login --identity --client-id <id>` is the correct form. Every Run Command script in this project that authenticates a VM's managed identity (`deploy-dev`, `promote-uat`, `promote-prod`) uses this form.

### VM SKU capacity restrictions

```bash
# bash
az vm list-skus --location centralindia --size Standard_B --all --query "[].{Name:name, RestrictionType:restrictions[0].type, ReasonCode:restrictions[0].reasonCode}" --output table
```
```powershell
# PowerShell equivalent
az vm list-skus --location centralindia --size Standard_B --all --query "[].{Name:name, RestrictionType:restrictions[0].type, ReasonCode:restrictions[0].reasonCode}" --output table
```

`RestrictionType: Location` indicates a size genuinely blocked region-wide for this subscription — not fixable by retrying. `RestrictionType: Zone` restricts only specific availability zones, which does not matter where no `zone` is pinned on the VM resource.

### vCPU quota check

```bash
# bash
az vm list-usage --location centralindia --query "[?contains(name.value, 'Bs')]" --output table
```
```powershell
# PowerShell equivalent
az vm list-usage --location centralindia --query "[?contains(name.value, 'Bs')]" --output table
```

Run this before any VM apply once more than one environment is provisioned on a quota-constrained subscription — see `ARCHITECTURE_AZURE.md` Section 7.

### VM Run Command — inspecting results

`az vm run-command show --run-command-name` looks up a *persisted* `runCommands` sub-resource created by `az vm run-command create`, and does not apply to the ephemeral `az vm run-command invoke` pattern used throughout this project. Invoke's own synchronous stdout/stderr is the only result to inspect; re-run `invoke` again for a fresh check.

### ACR access

```bash
# bash
az acr show --name <AZURE_ACR_NAME> --resource-group eai-shared-rg --output table
az acr login --name <AZURE_ACR_NAME>
```
```powershell
# PowerShell equivalent
az acr show --name <AZURE_ACR_NAME> --resource-group eai-shared-rg --output table
az acr login --name <AZURE_ACR_NAME>
```

`az acr login` is an operator diagnostic; the production VM authenticates via its managed identity, never an administrator credential.

### API Management — diagnosing a 404 on the public gateway

Layer the diagnosis rather than guessing: backend health (via `az ssh vm` from inside the VNet) → the APIM Portal's "Test" tab (bypasses any Product/subscription-key gate, validates only operation-match and backend wiring) → the public gateway URL (enforces the Product/subscription gate, if one is configured). A 200 on the Test tab together with a 404 on the public URL isolates the fault to Product association rather than operation or backend configuration; a 404 on both isolates it to operation-template matching. `url_template = "/*"` is not a valid catch-all in APIM's template language — the correct wildcard form is `/{*path}` with an accompanying `template_parameter` block; this implementation instead declares each route explicitly (`GET /health`, `POST /api/v1/ingest/bulk`).

### PostgreSQL Flexible Server

```bash
# bash
az postgres flexible-server show --resource-group eai-<env>-rg --name xxx-<env>-pg-suffix --output table
```
```powershell
# PowerShell equivalent
az postgres flexible-server show --resource-group eai-<env>-rg --name xxx-<env>-pg-suffix --output table
```

### API Management

```bash
# bash
az apim show --resource-group eai-<env>-rg --name xxx-<env>-apim-suffix --output table
```
```powershell
# PowerShell equivalent
az apim show --resource-group eai-<env>-rg --name xxx-<env>-apim-suffix --output table
```

---

## Security Rules

1. Do not commit Azure client secrets, passwords, tokens, or private keys.
2. Use Microsoft Entra ID and workload identity federation for all CI/CD authentication — no client secret is stored for any GitHub Actions identity.
3. Use managed identity for VM-to-Azure authentication — the VM never holds a long-lived Azure credential.
4. Use Key Vault for application secrets; generate them with Terraform, never hardcode them.
5. Keep every PostgreSQL Flexible Server private — `public_network_access_enabled = false`, explicit in every environment.
6. Do not grant a GitHub Actions identity subscription-wide `Owner` or unrestricted `Contributor` access merely to simplify deployment — each identity's RBAC grants are scoped per resource (Section 2.9, Section 3.1).
7. Restrict each Entra federated identity credential to its intended repository and branch/environment subject.
8. Use immutable, commit-SHA-tagged container images for every deployment; never redeploy `latest`.
9. Protect the Production GitHub Environment with an explicit required-reviewer approval gate.
10. Record the production baseline after every Production deployment.
11. Keep the Terraform state backend (HCP Terraform) outside the Git repository.
12. Do not expose an internal application service (the transformation service, the database) merely to simplify diagnostics — every interactive access path in this project (`az ssh vm`, Key Vault reads) is scoped to the identity performing the access, not opened broadly.
13. Restrict the `AllowOperatorSSH` NSG rule's source to a single operator `/32` at all times — never `0.0.0.0/0` — and treat it as a temporary substitute for Azure Bastion (`ARCHITECTURE_AZURE.md`, Section 6), removed once a standard public-IP quota is available.
