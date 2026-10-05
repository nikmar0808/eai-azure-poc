# Deployment Guide — Azure Implementation

This document describes how to deploy this project to an independent Microsoft Azure subscription. The deployment is a single environment on Azure Container Apps, built and updated by a GitHub Actions pipeline, as described in [`ARCHITECTURE_AZURE.md`](ARCHITECTURE_AZURE.md) and mapped resource by resource in [`INFRA_VIEW_AZURE.md`](INFRA_VIEW_AZURE.md). Design rationale is not repeated here. The three-environment, virtual-machine implementation is a separate repository, [`enterprise-integration-azure`](https://github.com/nikmar0808/enterprise-integration-azure).

This guide assumes the repository has been cloned and the local quickstart in the [README](../README.md) has been verified before any Azure resource is touched.

**A note on sequencing.** A clean rebuild has one circular dependency, and the order below is shaped by it. The Container Apps need images in the registry when they are first created; the pipeline normally publishes those images; but the pipeline's permission to push to the registry is granted by the same Terraform stack that creates the apps. The guide resolves this by pushing the first set of images once, by hand, from the operator's machine, and handing every later image to the pipeline. Each constraint of the free-tier subscription is stated where it applies, together with what a standard subscription would do instead.

---

## Prerequisites

| Requirement | Notes |
|---|---|
| Azure subscription | A free-tier subscription is sufficient. See [`ARCHITECTURE_AZURE.md`](ARCHITECTURE_AZURE.md), Section 4, for the quotas and product restrictions that apply to it |
| GitHub repository (a fork or clone of this project) | Actions and Environments must be enabled. Required-reviewer protection on an environment needs a public repository, or a paid plan for a private one |
| HCP Terraform account and organization | The free tier is sufficient |
| Azure CLI | A current version |
| Terraform CLI | `>= 1.5.0` |
| GitHub CLI (`gh`) | Authenticated (`gh auth login`) |
| Docker and Docker Compose | For local verification and the one-time first image push |
| Java 21, Python 3.14, Node 22 | For local application build and test |
| Microsoft Entra permission | The account running the bootstrap must be allowed to create app registrations |

## Placeholder Reference

Every command block below uses the placeholders in this table. **Replace all occurrences of `<...>` with the real values before running a command.** Resource-name conventions that are not account-specific (resource group names, app names) are left literal throughout this guide. Names that Azure requires to be globally unique (the registry and the Key Vault), and identifiers tied to one subscription, tenant or repository, are placeholders.

| Placeholder | Example value | How to obtain it |
|---|---|---|
| `<AZURE_SUBSCRIPTION_ID>` | `00000000-0000-0000-0000-000000000000` | `az account show --query id --output tsv` |
| `<AZURE_TENANT_ID>` | `00000000-0000-0000-0000-000000000000` | `az account show --query tenantId --output tsv` |
| `<AZURE_LOCATION>` | `centralindia` | The Azure region chosen for the deployment, used consistently throughout |
| `<GITHUB_ORG>` | `octocat` | The GitHub user or organization that owns the repository |
| `<REPO_NAME>` | `eai-azure-poc` | The repository name |
| `<GITHUB_OWNER_ID>` | `000000000` | `gh api repos/<GITHUB_ORG>/<REPO_NAME> --jq ".owner.id"` |
| `<GITHUB_REPO_ID>` | `0000000000` | `gh api repos/<GITHUB_ORG>/<REPO_NAME> --jq ".id"` |
| `<HCP_TERRAFORM_ORG>` | `my-tfc-org` | The organization name shown in HCP Terraform after sign-in |
| `<HCP_TERRAFORM_PROJECT>` | `my-tf-proj` | A project to organise the workspaces |
| `<HCP_TERRAFORM_WORKSPACE_SHARED>` | `my-shared-ws` | The workspace for the shared registry |
| `<HCP_TERRAFORM_WORKSPACE_ACA>` | `my-aca-ws` | The workspace for the application stack |
| `<AZURE_CLIENT_ID>` | `00000000-0000-0000-0000-000000000000` | Output `gha_deploy_dev_client_id` of the identity bootstrap (Part 1) |
| `<AZURE_ACR_NAME>` | `mysharedacr` | A globally unique registry name; check with `az acr check-name --name <AZURE_ACR_NAME>` |
| `<AZURE_ACR_RESOURCE_GROUP>` | `eai-shared-rg` | The resource group the shared registry is created in (Part 3) |
| `<ACR_LOGIN_SERVER>` | `mysharedacr.azurecr.io` | Output `acr_login_server` of the shared stack |
| `<AZURE_KEY_VAULT_NAME>` | `poc-eai-kv-ab12` | A globally unique Key Vault name; append a short random suffix |
| `<OPERATOR_IP>` | `203.0.113.7` | The operator's public address, as a `/32`; `Invoke-RestMethod https://api.ipify.org` or `curl ifconfig.me` |
| `<DEPLOY_SHA>` | a 40-character commit SHA | The commit whose images are being deployed |

---

## Part 0 — Local Development Verification

This part confirms the application layer works correctly, independently of any Azure resource, before cloud provisioning begins. The services (`01-java-ingestion-service`, `02-python-transformation-api`, `03-node-frontend`, `04-react-readings`) are cloud-agnostic.

```powershell
# PowerShell, from the repository root
Copy-Item .env.sample .env      # then set POSTGRES_PASSWORD and API_SECURITY_TOKEN to long random values
docker compose -f docker-compose.dev.yml up --build -d
docker compose -f docker-compose.dev.yml ps
Invoke-RestMethod -Uri http://localhost:8081/health
Invoke-RestMethod -Uri http://localhost:8082/health
```

```bash
# bash equivalent
cp .env.sample .env
docker compose -f docker-compose.dev.yml up --build -d
docker compose -f docker-compose.dev.yml ps
curl http://localhost:8081/health
curl http://localhost:8082/health
```

**Expected result.** All services report running; the Python health check returns `{"status":"UP","database":"UP"}` and the Java health check returns `{"status":"UP","pythonValidator":"UP"}`. Open `http://localhost:3000`, submit a reading, then open `http://localhost:8080` and look it up. Stop the stack before continuing:

```powershell
docker compose -f docker-compose.dev.yml down
```

---

## Part 1 — Azure Identity Bootstrap

### 1.1 Azure CLI authentication

```powershell
az login
az account list --output table
az account set --subscription "<AZURE_SUBSCRIPTION_ID>"
az account show --query "{subscriptionId:id,subscriptionName:name,tenantId:tenantId,user:user.name}" --output json
```

**Confirm the output before proceeding:** `subscriptionId` and `tenantId` match the values recorded. Every later step assumes this exact account is active.

### 1.2 Resource provider registration

Registration is asynchronous and free. Register the namespaces this deployment uses and confirm each reads `Registered`:

```powershell
$providers = "Microsoft.App","Microsoft.ContainerRegistry","Microsoft.KeyVault","Microsoft.ManagedIdentity","Microsoft.OperationalInsights","Microsoft.Insights"
foreach ($ns in $providers) { az provider register --namespace $ns }
foreach ($ns in $providers) { "$ns : " + (az provider show --namespace $ns --query registrationState --output tsv) }
```

```bash
# bash equivalent
for ns in Microsoft.App Microsoft.ContainerRegistry Microsoft.KeyVault Microsoft.ManagedIdentity Microsoft.OperationalInsights Microsoft.Insights; do
  az provider register --namespace "$ns"
done
for ns in Microsoft.App Microsoft.ContainerRegistry Microsoft.KeyVault Microsoft.ManagedIdentity Microsoft.OperationalInsights Microsoft.Insights; do
  echo "$ns : $(az provider show --namespace $ns --query registrationState --output tsv)"
done
```

Repeat the second command until every line ends in `Registered`.

### 1.3 Identity bootstrap Terraform configuration

A one-time, locally applied Terraform root with its own separate state creates only the Microsoft Entra applications, service principals and federated credentials (see [`INFRA_VIEW_AZURE.md`](INFRA_VIEW_AZURE.md), Section 3). It creates no application infrastructure. This resolves a circularity: an identity cannot authenticate the very Terraform run that creates it.

**File to modify:** `infra/bootstrap/terraform.tfvars.sample`. Rename it to `terraform.tfvars` (the file is git-ignored) and replace the content:

```hcl
azure_tenant_id         = "<AZURE_TENANT_ID>"
azure_subscription_id   = "<AZURE_SUBSCRIPTION_ID>"
github_org              = "<GITHUB_ORG>"
github_owner_id         = "<GITHUB_OWNER_ID>"
repo_name               = "<REPO_NAME>"
github_repo_id          = "<GITHUB_REPO_ID>"
hcp_terraform_org       = "<HCP_TERRAFORM_ORG>"

# Declared by the configuration but not consumed by this implementation; a value is still required.
hcp_terraform_ws_shared = "<HCP_TERRAFORM_WORKSPACE_SHARED>"
hcp_terraform_ws_dev    = "unused"
hcp_terraform_ws_uat    = "unused"
hcp_terraform_ws_prod   = "unused"
```

**Apply:**

```powershell
Set-Location infra\bootstrap
terraform init
terraform plan
terraform apply
terraform output -raw gha_deploy_dev_client_id
```

```bash
# bash equivalent
cd infra/bootstrap
terraform init
terraform plan
terraform apply
terraform output -raw gha_deploy_dev_client_id
```

Read the plan before applying: it should create Entra applications, service principals and federated credentials only. **Record `gha_deploy_dev_client_id` as `<AZURE_CLIENT_ID>`.** The CI identity's single federated credential trusts a job that declares the GitHub Environment `poc`; the subject contains the owner and repository IDs, which is why they must be correct. Any later edit to this folder has no effect until `terraform apply` is run inside `infra/bootstrap` specifically.

### 1.4 HCP Terraform workspace configuration

Create a project named `<HCP_TERRAFORM_PROJECT>` in the HCP Terraform web interface, organization `<HCP_TERRAFORM_ORG>`. Create two workspaces (CLI-driven workflow), each with **Execution Mode → Local**: `<HCP_TERRAFORM_WORKSPACE_SHARED>` and `<HCP_TERRAFORM_WORKSPACE_ACA>`. Authenticate the CLI with `terraform login`.

**No workspace variables are required.** Under Local Execution Mode, HCP Terraform never runs `plan` or `apply`; it is a remote state backend only. What authenticates a local `terraform apply` is the `az login` session from Part 1.1: the `azurerm` provider falls back to the active Azure CLI session when no explicit credentials are present.

Update the `cloud { }` block in `infra/shared/main.tf` and `infra/aca/main.tf` so that `organization` and the workspace `name` match the values above.

---

## Part 2 — Region and Name Availability

Confirm the chosen region offers what the stack needs, and that the globally unique names are free:

```powershell
az account list-locations --query "[?name=='<AZURE_LOCATION>'].{name:name,displayName:displayName}" --output table
az acr check-name --name <AZURE_ACR_NAME> --output table
```

An Azure Container Apps environment on the Consumption plan does not consume a virtual-machine quota or a public IP. A free-tier subscription still limits some products by subscription type; creating a resource is the only reliable test (Azure Front Door, for example, is refused outright on free-trial accounts, and no edge layer is used here for that reason).

---

## Part 3 — Shared Container Registry

The registry is provisioned once, in its own resource group and workspace. It is never destroyed as part of an application-stack teardown, and the application stack finds it by a read-only lookup.

**File to modify:** `infra/shared/terraform.tfvars.sample`. Rename it to `terraform.tfvars` and set `acr_name = "<AZURE_ACR_NAME>"`, together with the same tenant, subscription and repository values used in Part 1.3. The remaining declared variables are not consumed by this folder but still need a value.

```powershell
Set-Location infra\shared
terraform init
terraform plan
terraform apply
terraform output -raw acr_login_server
```

**Record `acr_login_server` as `<ACR_LOGIN_SERVER>`** (it resolves to `<AZURE_ACR_NAME>.azurecr.io`). The registry's resource group is `<AZURE_ACR_RESOURCE_GROUP>` (`eai-shared-rg`).

---

## Part 4 — The One-Time First Image Push

**Why this step exists.** The Container Apps are created with an image reference and fail to start if the tag does not exist in the registry. The pipeline would normally publish the images, but its permission to push is granted in Part 5, by the same stack that creates the apps. The first set of images is therefore pushed once, by the operator, who holds the rights to do so. From the next change onward the pipeline builds every image, and this step never recurs.

Before building, confirm each image folder keeps local files out of the image. The two Node folders contain a `.dockerignore` that excludes `node_modules`, `dist` and `.env`; the Java and Python folders must not copy a local `.env`. Then, from the repository root:

```powershell
$sha = (git rev-parse HEAD)
az acr login --name <AZURE_ACR_NAME>
docker build -t "<ACR_LOGIN_SERVER>/eai-java-gateway:$sha"     ./01-java-ingestion-service
docker build -t "<ACR_LOGIN_SERVER>/eai-python-validator:$sha" ./02-python-transformation-api
docker build -t "<ACR_LOGIN_SERVER>/eai-node-frontend:$sha"    ./03-node-frontend
docker build -t "<ACR_LOGIN_SERVER>/eai-react-readings:$sha"   ./04-react-readings
docker push "<ACR_LOGIN_SERVER>/eai-java-gateway:$sha"
docker push "<ACR_LOGIN_SERVER>/eai-python-validator:$sha"
docker push "<ACR_LOGIN_SERVER>/eai-node-frontend:$sha"
docker push "<ACR_LOGIN_SERVER>/eai-react-readings:$sha"
```

**Record `$sha` as `<DEPLOY_SHA>`.** Verify:

```powershell
az acr repository show-tags --name <AZURE_ACR_NAME> --repository eai-react-readings --orderby time_desc --detail --output table
```

**Expected result.** `<DEPLOY_SHA>` is at the top of the list (repeat for the other three repositories). `--orderby time_desc` matters: without it the newest tag does not reliably sort first.

*A refinement a team may prefer:* create the apps from a public placeholder image and let the pipeline's first deployment set the real tag, which removes this manual step. The Terraform in this repository ignores changes to the image, so that change is confined to the initial `image` value.

---

## Part 5 — Application Stack

Applied against workspace `<HCP_TERRAFORM_WORKSPACE_ACA>`.

**File to modify:** `infra/aca/terraform.tfvars.sample`. Rename it to `terraform.tfvars` (git-ignored) and set:

```hcl
gha_deploy_client_id = "<AZURE_CLIENT_ID>"
acr_name             = "<AZURE_ACR_NAME>"
acr_resource_group   = "<AZURE_ACR_RESOURCE_GROUP>"
key_vault_name       = "<AZURE_KEY_VAULT_NAME>"
operator_ip_cidr     = "<OPERATOR_IP>/32"
```

In `infra/aca/apps.tf`, set the `image` line of each of the four application resources to use `<DEPLOY_SHA>` (the tag pushed in Part 4). The Terraform ignores later changes to that field, because the pipeline owns the running version.

```powershell
Set-Location infra\aca
terraform init
terraform plan
terraform apply
```

Read the plan first. It should create the resource group, the managed identity, Log Analytics, the Container Apps environment, the Key Vault with its secrets, five Container Apps, and the role assignments listed in [`INFRA_VIEW_AZURE.md`](INFRA_VIEW_AZURE.md). The Container Apps Environment is the slowest resource; several minutes is normal.

**Expected result.** `Apply complete!`, and these outputs:

```powershell
terraform output -raw node_frontend_fqdn
terraform output -raw react_readings_fqdn
az containerapp list --resource-group poc-eai-aca-rg --query "[].{name:name,state:properties.runningStatus}" --output table
```

All five apps are listed. A freshly created app that scales to zero may report no running replica until it receives a request.

**If it fails.** A `403` creating a role assignment means the signed-in account lacks `Microsoft.Authorization/roleAssignments/write` on that scope. A Key Vault `Forbidden` while creating the secrets means the operator's `Key Vault Secrets Officer` assignment has not propagated yet; run `terraform apply` again, since Terraform already orders the assignment before the secrets. An image-pull failure with a revision that never reaches a healthy state means the `image` tag does not exist in the registry: check Part 4. A literal placeholder such as `<sha>` left in an `image` line is not a registry error; it is an invalid tag.

---

## Part 6 — GitHub Configuration

### 6.1 Repository variables

Repository → **Settings → Secrets and variables → Actions → Variables → New repository variable**. The values are identifiers and names, not passwords, so they are variables and not secrets.

| Variable | Value |
|---|---|
| `AZURE_TENANT_ID` | `<AZURE_TENANT_ID>` |
| `AZURE_SUBSCRIPTION_ID` | `<AZURE_SUBSCRIPTION_ID>` |
| `ACR_NAME` | `<AZURE_ACR_NAME>` (the short name, not the `.azurecr.io` address) |
| `AZURE_CLIENT_ID` | `<AZURE_CLIENT_ID>` |

The resource group and application names are constants in the workflow, because Terraform declares the same literals and a variable would be a second copy that Terraform never reads. If an app is ever renamed in Terraform, the workflow must change with it.

### 6.2 Repository secret

Create one secret, `GITLEAKS_PROJECT_REGEX` (Secrets tab). It holds the pattern of a retired project value that the secret scan must never find. Its value is deliberately not stored in the repository, and the scan fails with a clear message if it is missing.

### 6.3 The `poc` environment

An environment is a named checkpoint: a job that declares it is held by GitHub until the rules are satisfied. Repository → **Settings → Environments → New environment** → name exactly `poc` (lower case).

1. Tick **Required reviewers** and add the repository owner. **Leave "Prevent self-review" unticked**: with one person on the project, ticking it would make every approval impossible.
2. If the page shows **Allow administrators to bypass configured protection rules**, untick it. An administrator's run may otherwise skip the wait.
3. Under **Deployment branches and tags**, choose **Selected branches and tags** and add `develop`.
4. **Save protection rules**, then re-open the page and confirm the reviewer is still listed. An environment with no saved rule is only a name.

The name must match in three places: the GitHub Environment, the workflow's `environment:` lines, and the subject of the federated credential created in Part 1.3. If a workflow names an environment that does not exist, GitHub silently creates an unprotected one and runs the job straight through, so the pause in Part 7 is how the gate is proved.

### 6.4 Branch protection and scanning

Create a branch ruleset for `develop` (and `main`) that requires a pull request and requires the status checks `secret-scan`, `dependency-scan`, `java-build-test`, `python-build-test`, `node-build-check`, `react-build`, and the four `image-scan` jobs. Enable **Secret scanning** and **Push protection** under **Settings → Code security**; both are free for public repositories.

---

## Part 7 — Pipeline: Publish and Deploy

### 7.1 Publish images

Push a change to `develop` through a pull request. After the scans and builds pass, the `publish-images` job shows **Waiting for review**. Open the run in the **Actions** tab, choose **Review deployments**, tick `poc`, and **Approve and deploy**. The job then builds the four images, scans each, and pushes them tagged with the merge commit's SHA. If the job does not pause, the environment has no saved reviewer rule (return to Part 6.3) before anything is approved.

Record the merge commit's SHA as `<DEPLOY_SHA>` and confirm all four repositories list it first:

```powershell
git checkout develop
git pull
git log -1 --format=%H
az acr repository show-tags --name <AZURE_ACR_NAME> --repository eai-java-gateway --orderby time_desc --detail --output table
```

### 7.2 Deploy by tag

Deployment is a separate run, started by hand, and never builds:

```powershell
gh workflow run ci.yml --ref develop -f image_tag=<DEPLOY_SHA>
gh run list --workflow ci.yml --limit 1
gh run watch <run-id>
```

The run pauses for approval exactly as above. After approval it confirms that the four tags exist, updates the four application Container Apps to those tags, and waits until each new revision reports `Provisioned`. (If `gh` cannot find the workflow, the workflow file on the default branch lacks the dispatch trigger.)

### 7.3 Confirm Terraform and the pipeline agree

```powershell
Set-Location infra\aca
terraform plan
```

**Expected result.** `No changes.` The pipeline changed the image; Terraform has been told to ignore that field, so the two do not fight.

---

## Part 8 — Verification

The two external apps accept traffic only from `<OPERATOR_IP>`, so functional checks are made from that address. A GitHub runner cannot make them.

**Write path and read path, from the operator's machine.** Open `https://<node_frontend_fqdn>`, submit a reading, then open `https://<react_readings_fqdn>` and look the meter up. Both addresses come from the Terraform outputs.

**The row reached the database.** PostgreSQL has no public endpoint; reach it from inside the environment:

```powershell
az containerapp exec --name poc-eai-postgres --resource-group poc-eai-aca-rg --command "psql -U smart_meter_admin -d smart_meter_warehouse -c \"SELECT * FROM smart_meter_intervals ORDER BY id DESC LIMIT 3;\""
```

**Logs and revisions.**

```powershell
az containerapp logs show --name poc-eai-python-validator --resource-group poc-eai-aca-rg --type console --tail 30
az containerapp revision list --name poc-eai-python-validator --resource-group poc-eai-aca-rg --output table
```

**The exposure model holds.** From a different network (for example a phone on mobile data), both external addresses return `403` almost immediately, because the platform rejects them at the edge. The internal apps have no public endpoint at all, so a request to them fails to connect or resolve, which is a stronger result than a `403`.

**Expected result.** The submitted reading appears in the database and on the read screen; the Python log shows a clean start; the newest revision of each app is running.

---

## Part 9 — Monitoring

Alert rules and the dashboard are created with the Azure CLI and the portal and are not managed by Terraform. Delete them before destroying the stack (Part 11). Confirm telemetry is flowing first. The workspace ID is the GUID shown on the Log Analytics workspace `poc-eai-law`:

```powershell
$workspaceId = az monitor log-analytics workspace show --resource-group poc-eai-aca-rg --workspace-name poc-eai-law --query customerId -o tsv
az monitor log-analytics query --workspace $workspaceId --analytics-query "ContainerAppConsoleLogs_CL | take 5"
```

**An action group, so that alerts notify someone:**

```powershell
az monitor action-group create --name "poc-eai-alerts" --resource-group poc-eai-aca-rg --action email operator "<operator e-mail address>"
```

**Restart-count alerts** for the services whose crash would matter most:

```powershell
az monitor metrics alert create `
  --name "poc-eai-python-validator-high-restart" `
  --resource-group poc-eai-aca-rg `
  --scopes (az containerapp show --name poc-eai-python-validator --resource-group poc-eai-aca-rg --query id -o tsv) `
  --condition "total RestartCount > 0" --window-size 5m --evaluation-frequency 1m --severity 2 `
  --action poc-eai-alerts `
  --description "Fires if the Python service restarts in a 5-minute window."
```

Repeat for `poc-eai-java-gateway`. A restart-count alert detects a process that crashes, which is what an unparseable `DATABASE_URL` produces. It does not detect a live process whose downstream dependency is failing.

**A request-level error alert** covers that second case, by querying the console log:

```powershell
$workspaceResourceId = az monitor log-analytics workspace show --resource-group poc-eai-aca-rg --workspace-name poc-eai-law --query id -o tsv
az monitor scheduled-query create `
  --name "poc-eai-error-rate" `
  --resource-group poc-eai-aca-rg `
  --scopes $workspaceResourceId `
  --condition "total 'Errors' > 0" `
  --condition-query Errors="ContainerAppConsoleLogs_CL | where ContainerAppName_s == 'poc-eai-python-validator' | where Log_s contains 'ERROR'" `
  --window-size 5m --evaluation-frequency 5m --severity 1 `
  --action-groups poc-eai-alerts
```

(The syntax of `scheduled-query` has changed between CLI versions; `--help` is the authority.)

**A dashboard.** In the portal: **Dashboard → New dashboard → Blank**, name it `poc-eai-window`, and add a Log Analytics tile for `poc-eai-law` with a query such as:

```kusto
ContainerAppConsoleLogs_CL
| where ContainerAppName_s == "poc-eai-python-validator"
| summarize Lines = count() by bin(TimeGenerated, 5m)
| render timechart
```

Log Analytics is configured with a one-gigabyte daily ingestion cap as a cost safety net; if ingestion approaches it, raise the cap deliberately in Terraform rather than removing it.

---

## Part 10 — Rollback

Rollback is the same mechanism as deployment, pointed at an older tag; it is not a separate emergency procedure. List the available tags, identify the last known-good SHA, and deploy it:

```powershell
az acr repository show-tags --name <AZURE_ACR_NAME> --repository eai-java-gateway --orderby time_desc --detail --output table
gh workflow run ci.yml --ref develop -f image_tag=<ROLLBACK_SHA>
```

The run pauses at the same approval gate: a rollback is not exempt, because the gate exists for precisely the moment a change, forward or backward, is made under pressure. Afterwards repeat the Part 8 checks against the rolled-back tag. A defect that caused a rollback is fixed at the source and re-validated through a pull request in full before another deployment; the defective SHA is not redeployed.

**This depends on the registry still holding the older tag.** No retention policy is defined on the registry in this implementation, so confirm the target tag appears in the listing before relying on it. A steady-state deployment should add an explicit retention policy that keeps a number of recent tags.

---

## Part 11 — Teardown

The environment runs on a time-limited credit and is destroyed deliberately. Take every Azure-hosted record (dashboards, alert lists, registry tag listings, cost analysis) before starting, because they disappear with the resources. Records that live in GitHub survive.

**11.1 Inventory first.**

```powershell
az group list --output table
az resource list --output table
```

**11.2 Remove what Terraform does not manage, then destroy the stack.** The `azurerm` provider refuses to delete a resource group that contains resources it does not manage, so the alert rules and action group created in Part 9 must go first:

```powershell
az monitor metrics alert delete --name "poc-eai-java-gateway-high-restart" --resource-group poc-eai-aca-rg
az monitor metrics alert delete --name "poc-eai-python-validator-high-restart" --resource-group poc-eai-aca-rg
az monitor scheduled-query delete --name "poc-eai-error-rate" --resource-group poc-eai-aca-rg --yes
az monitor action-group delete --name "poc-eai-alerts" --resource-group poc-eai-aca-rg

Set-Location infra\aca
terraform plan -destroy
terraform destroy
```

Read the destroy plan before approving. It should list only resources in `poc-eai-aca-rg`: the resource group, the identity, Log Analytics, the environment, the Key Vault with its secrets, five Container Apps, and the role assignments (including the two for the CI identity, one of which is scoped to the shared registry). Nothing from the shared resource group should appear. Confirm with `az group show --name poc-eai-aca-rg`, which should report that the group is not found.

**11.3 Delete the portal dashboard.** Portal dashboards default to a resource group named `dashboards`. Delete only the dashboard you created, unless that group holds nothing else.

**11.4 Purge the soft-deleted Key Vault.** The vault is soft-deleted for seven days, and its name stays reserved until purged, which matters if the stack is rebuilt with the same name:

```powershell
az keyvault list-deleted --output table
az keyvault purge --name <AZURE_KEY_VAULT_NAME>
```

**11.5 Decide about the shared registry and the identities.**

- **The registry** bills a small daily amount whether or not it is used. Every image is rebuilt by the pipeline from the repository, so on a time-limited subscription it is destroyed: `terraform destroy` in `infra/shared`, after reading its plan. A live organisation keeps its registry and sets a retention policy.
- **The bootstrap identities** cost nothing and live in the Entra tenant, not the subscription, so they survive the subscription being disabled. They hold no roles once the stack is gone. Leave them, to avoid repeating Part 1.3 on a rebuild.
- **GitHub and HCP Terraform** settings (the `poc` environment, variables, the secret, the ruleset, the workspaces) are inputs to a rebuild and are left in place.

After the registry is destroyed, do not approve a pending `publish-images` run or dispatch a deployment: both would fail at the registry.

**11.6 Verify no running cost remains.**

```powershell
az group list --output table
az resource list --output table
az keyvault list-deleted --output table
az containerapp env list --output table
```

Only `NetworkWatcherRG`, which Azure creates itself and which is free, should remain. Cost data lags by roughly 8 to 24 hours, so look at cost analysis again the next day. Keep any budget alert in place; it is free and protects against a resource created by mistake.

---

## Troubleshooting Reference

### Azure CLI identity and subscription

```powershell
az account show
az account list --output table
az account set --subscription "<AZURE_SUBSCRIPTION_ID>"
```

### A pipeline login fails

`AADSTS70021: No matching federated identity record found` means the job's token subject matches no federated credential. The error prints the subject Azure received; compare it character for character with the credential's subject (the environment name must be `poc`, lower case, in the GitHub Environment, the workflow and the credential). `AuthorizationFailed` on a push or an update means a role assignment is missing, or was created a moment ago and has not propagated: `az role assignment list --assignee <AZURE_CLIENT_ID> --all --output table`, then retry after a minute.

### An approval never appears

The job ran straight through: the environment has no saved reviewer rule, or administrator bypass is enabled (Part 6.3). A login that still succeeded shows only that the environment *name* is right.

### Scan jobs

`TOOMANYREQUESTS` while Trivy downloads its database, or an HTTP 429 from the Maven repository, is a rate limit on shared runner addresses, not a finding: re-run the failed job. A failing dependency or image scan lists each finding with its package, installed version and fixed version in the job log; fix the dependency or record an expiring exception in the ignore file. A secret-scan failure that names a commit and a file is read with the secret-handling order in mind: rotate or revoke first, then remove, and only then consider rewriting history.

### A Container App revision does not become healthy

```powershell
az containerapp logs show --name <app name> --resource-group poc-eai-aca-rg --type console --tail 50
az containerapp logs show --name <app name> --resource-group poc-eai-aca-rg --type system --tail 50
az containerapp revision list --name <app name> --resource-group poc-eai-aca-rg --output table
```

The Python service validates its configuration when it starts: an unparseable `DATABASE_URL` or a missing token makes the process exit before it serves, and the revision shows as unhealthy. A `Secret reference ... could not be resolved` error means the managed identity's `Key Vault Secrets User` assignment has not propagated, or the identity named in the secret block is not the one granted the role.

### An external app returns 403

The operator's public address changed (common on home connections). Update `operator_ip_cidr` in `terraform.tfvars` and re-apply. Fix a wrong value by re-applying the corrected one, never by destroying resources.

### The registry

```powershell
az acr show --name <AZURE_ACR_NAME> --resource-group <AZURE_ACR_RESOURCE_GROUP> --output table
az acr login --name <AZURE_ACR_NAME>
```

`az acr login` is an operator diagnostic; the apps pull images through their managed identity, never an administrator credential.

---

## Security Rules

1. Do not commit Azure client secrets, passwords, tokens, private keys, or a `.env` or `terraform.tfvars` file.
2. Use Microsoft Entra ID and workload identity federation for all CI/CD authentication; no client secret is stored for any GitHub Actions identity.
3. Use managed identity for app-to-Azure authentication; an app never holds a long-lived Azure credential.
4. Keep application secrets in Key Vault, generate them with Terraform, and never hardcode them or pass them through the pipeline.
5. Keep internal services internal: the Python service, the Java gateway and the database have no public endpoint, and the two public endpoints are restricted to an allow-listed address.
6. Do not grant the CI identity subscription-wide `Owner` or `Contributor`; its roles are scoped to one resource group and one registry.
7. Restrict each federated credential to its intended repository and environment subject.
8. Use immutable, commit-SHA-tagged images for every deployment; never deploy `latest`, and never rebuild a tag.
9. Protect the `poc` environment with a required-reviewer rule, and confirm by observation that it actually pauses a run.
10. Fail the build on actionable vulnerabilities and on leaked secrets, record accepted findings with a reason and an expiry date, and rotate before removing when a real credential is found.
11. Keep the Terraform state backend outside the Git repository.
12. Do not expose an internal service merely to simplify diagnostics; operator access is through the Azure control plane (`az containerapp logs`, `az containerapp exec`), scoped to the identity performing it.
