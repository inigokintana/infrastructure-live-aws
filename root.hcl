# Root Terragrunt configuration for AWS infrastructure-live
# Provides AWS provider and S3 backend configuration for all stacks

terraform_binary = "tofu"

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  region_vars = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  account_name = local.account_vars.locals.account_name
  account_id = local.account_vars.locals.account_id
  aws_region = local.region_vars.locals.aws_region
}

# Generate AWS provider
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOT
    terraform {
      required_version = ">= 1.0"
      required_providers {
        aws = {
          source  = "hashicorp/aws"
          version = "~> 5.0"
        }
      }
    }

    provider "aws" {
      region              = "${local.aws_region}"
      allowed_account_ids = ["${local.account_id}"]

      default_tags {
        tags = {
          Environment = "${local.account_name}"
          ManagedBy   = "Terragrunt"
          Stack       = "${path_relative_to_include()}"
        }
      }
    }
  EOT
}

# Configure S3 remote state backend
remote_state {
  backend = "s3"
  config = {
    encrypt         = true
    bucket          = "terragrunt-state-${local.account_name}-${local.aws_region}-${local.account_id}"
    key             = "${path_relative_to_include()}/terraform.tfstate"
    region          = local.aws_region
    dynamodb_table  = "tf-locks-aws-${local.account_id}"
    skip_region_validation      = false
    skip_credentials_validation = false
  }
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
}

# Catalog reference
catalog {
  urls = [
    "git::https://github.com/inigokintana/terragrunt-infrastructure-catalog.git"
  ]
}
