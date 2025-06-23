data "aws_availability_zones" "available" {}

data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

data "aws_vpc" "selected" {
  filter {
    name   = "tag:env"
    values = [local.env]
  }
}

data "aws_subnets" "private_subnet" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.selected.id]
  }
  tags = {
    "Type" = "private"
  }
}

data "aws_subnets" "public_subnet" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.selected.id]
  }
  tags = {
    "Type" = "public"
  }
}

data "aws_ecr_image" "app_image" {
  repository_name = local.app
  image_tag       = local.app_version
}

data "aws_acm_certificate" "selected" {
  domain   = local.env == "prod" ? "${local.prod_domain}" : "*.${local.env}.${local.non_prod_domain}"
  statuses = ["ISSUED"]
}

data "aws_ecs_cluster" "selected" {
  cluster_name = "${local.env}-ecs-cluster"
}

data "aws_secretsmanager_secret" "selected" {
  name = "${local.env}/datadog/api-key"
}

data "aws_secretsmanager_secret_version" "selected" {
  secret_id = data.aws_secretsmanager_secret.selected.id
}