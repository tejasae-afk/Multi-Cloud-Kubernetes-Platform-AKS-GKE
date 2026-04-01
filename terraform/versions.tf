terraform {
  required_version = ">= 1.14.0, < 2.0.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 7.25.0, < 8.0.0"
    }

    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.66.0, < 5.0.0"
    }
  }
}
