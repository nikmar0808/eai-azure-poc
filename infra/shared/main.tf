terraform {
  cloud {
    organization = "MyOtg"
    workspaces {
      name = "eai-shared-azure"
    }
  }
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 4.0" }
  }
  required_version = ">= 1.5.0"
}

provider "azurerm" {
  features {}
}
