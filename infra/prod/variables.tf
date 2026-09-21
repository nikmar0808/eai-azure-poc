variable "azure_tenant_id" {
  type      = string
  sensitive = true
}

variable "azure_subscription_id" {
  type      = string
  sensitive = true
}

variable "github_org" {
  type = string
}

variable "github_owner_id" {
  type = string
}

variable "repo_name" {
  type = string
}

variable "github_repo_id" {
  type = string
}

variable "hcp_terraform_org" {
  type = string
}

variable "hcp_terraform_ws_shared" {
  type = string
}

variable "hcp_terraform_ws_prod" {
  type = string
}

variable "gha_deploy_client_id" {
  type      = string
  sensitive = true
}

variable "acr_name" {
  type = string
}

variable "operator_ip_cidr" {
  type        = string
  description = "Operator's public IP, as a /32 CIDR, permitted to reach the VM's SSH port directly."
}

variable "key_vault_name" {
  type = string
}

variable "postgres_server_name" {
  type = string
}

variable "apim_name" {
  type = string
}
