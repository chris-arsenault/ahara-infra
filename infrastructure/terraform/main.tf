terraform {
  required_version = ">= 1.14"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }

  backend "s3" {
    region       = "us-east-1"
    key          = "ahara/infra.tfstate"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = {
      Project   = local.prefix
      ManagedBy = "Terraform"
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

module "control" {
  source = "./control"
}

module "network" {
  source = "./network"
}

module "services" {
  source = "./services"

  vpc_id                         = module.network.vpc_id
  private_subnet_ids             = module.network.private_subnet_ids
  alb_listener_arn               = module.network.alb_listener_arn
  alb_dns_name                   = module.network.alb_dns_name
  alb_zone_id                    = module.network.alb_zone_id
  alb_sg_id                      = module.network.alb_sg_id
  ahara_lambda_sg_id             = module.network.ahara_lambda_sg_id
  vpn_client_sg_id               = module.network.vpn_client_sg_id
  route53_zone_id                = module.network.route53_zone_id
  reverse_proxy_target_group_arn = module.network.reverse_proxy_target_group_arn
  reverse_proxy_cognito_hosts    = module.network.reverse_proxy_cognito_hosts
}
