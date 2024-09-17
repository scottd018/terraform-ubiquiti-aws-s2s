terraform {
  required_providers {
    unifi = {
      source  = "paultyng/unifi"
      version = "0.41.0"
    }

    http = {
      source  = "hashicorp/http"
      version = "3.4.5"
    }

    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.20.0"
    }
  }
}

provider "unifi" {
  username = var.usg_username
  password = var.usg_password
  api_url  = var.usg_api_url

  allow_insecure = true
}

provider "aws" {
  region = var.aws_region
}
