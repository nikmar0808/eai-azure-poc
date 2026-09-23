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

variable "hcp_terraform_ws_dev" {
  type = string
}

variable "hcp_terraform_ws_uat" {
  type = string
}

variable "hcp_terraform_ws_prod" {
  type = string
}
