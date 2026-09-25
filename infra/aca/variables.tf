variable "gha_deploy_client_id" {
    type = string
    sensitive = true
}
# EXISTING shared registry's name — nothing new is created
variable "acr_name" {
    type = string 
}
# EXISTING resource group the EXISTING shared registry actually lives in
variable "acr_resource_group" {
    type = string
}
# globally unique — this one IS new
variable "key_vault_name" {
    type = string
}
