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

variable "acr_name" {
  type = string
}

variable "operator_ip_cidr" {
  type        = string
  description = "Operator's public IP, as a /32 CIDR, permitted to reach the VM's SSH port directly."
}
