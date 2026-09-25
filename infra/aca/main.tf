terraform {
  cloud {
    organization = "MyOtg"
    workspaces {
      name = "poc-eai-aks-azure"  # name retained from the original AKS plan (task 7.8);
                                    # this window's work is Container Apps, not AKS — see
                                    # Part 1 of this document for why. Renaming the workspace
                                    # buys nothing and costs a state-migration cycle, so it stays.
    }
  }
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 4.0" }
    azuread = { source = "hashicorp/azuread", version = "~> 3.0" }
    random  = { source = "hashicorp/random", version = "~> 3.6" }
  }
  required_version = ">= 1.5.0"
}

provider "azurerm" {
    features {}
}
provider "azuread" {}
provider "random" {}

resource "azurerm_resource_group" "poc_aca" {
  name     = "poc-eai-aca-rg"
  location = "centralindia"
  tags     = { Project = "eai-azure-poc", Phase = "azure-window-B" }
}
