terraform {
  required_version = ">= 1.6.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.29.0"
    }
  }
  cloud {
    organization = "grubmarket"

    workspaces {
      name = "test-nevermore-poc-ecr"
    }
  }
}

provider "aws" {
  region = "us-east-2"
}

locals {
  env  = "test"
  app  = "nevermore-poc"
  team = "wholesaleware"

  tags = {
    app       = local.app
    env       = local.env
    team      = local.team
    Terraform = "True"
  }
}

resource "aws_ecr_repository" "main" {
  name                 = local.app
  image_tag_mutability = "MUTABLE"

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = local.tags
}