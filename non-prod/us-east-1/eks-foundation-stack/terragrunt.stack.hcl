# Stack configuration for AWS EKS Foundation in non-production

locals {
  stack_name = "eks-foundation"
  environment = "non-prod"
  region      = "us-east-1"
}

unit "vpc" {
  source = "git::https://github.com/inigokintana/terragrunt-infrastructure-catalog.git//units/aws-vpc?ref=${values.version}"
  # source = "${get_repo_root()}/terragrunt-infrastructure-catalog/units/aws-vpc"
  #source = "../../../../terragrunt-infrastructure-catalog/units/aws-vpc"
  #source = "/home/inigokintana/IaC-SovereignCloudAI/terragrunt-infrastructure-catalog/units/aws-vpc"
  path   = "vpc"

  values = {
    #version              = values.version # commented for source local test
    version              = values.version # uncommented for source NON local test
    vpc_cidr             = "10.100.0.0/16"
    availability_zones   = try(values.availability_zones, ["us-east-1a", "us-east-1b"])
    enable_nat           = try(values.enable_nat, true)
    tags = {
      Stack       = local.stack_name
      Environment = local.environment
      ManagedBy   = "Terragrunt"
    }
  }
}

unit "eks" {
  source = "git::https://github.com/inigokintana/terragrunt-infrastructure-catalog.git//units/aws-eks?ref=${values.version}"
  # source = "${get_repo_root()}/terragrunt-infrastructure-catalog/units/aws-eks"
  #source = "../../../../terragrunt-infrastructure-catalog/units/aws-eks"
  #source = "/home/inigokintana/IaC-SovereignCloudAI/terragrunt-infrastructure-catalog/units/aws-eks"
  path   = "eks"

  values = {
    #version              = values.version # commented for source local test
    version              = values.version # uncommented for source NON local test
    cluster_name             = "non-prod-eks-primary"
    kubernetes_version       = try(values.kubernetes_version, "1.32")
    # vpc_path                 = unit.vpc.path
    node_group_desired_size  = try(values.node_group_desired_size, 2)
    node_group_min_size      = try(values.node_group_min_size, 1)
    node_group_max_size      = try(values.node_group_max_size, 4)
    node_instance_type       = try(values.node_instance_type, "t3.medium")
    tags = {
      Stack       = local.stack_name
      Environment = local.environment
      ManagedBy   = "Terragrunt"
    }
  }
}
