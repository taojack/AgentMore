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
      name = "test-nevermore-poc-ecs"
    }
  }
}

provider "aws" {
  region = "us-east-2"
}

locals {
  env         = "test"
  app         = "nevermore-poc"
  team        = "wholesaleware"
  app_port    = 8080
  app_version = "c54a9bb"

  desired_count = 1
  task_cpu      = 4096
  task_memory   = 8192
  app_cpu       = 2048
  app_memory    = 4096

  health_check = "/health"

  prod_domain     = "*.wholesaleware.com"
  non_prod_domain = "gbmt.io"

  env_vars = [
    { name = "ENV", value = local.env },
    { name = "REGION", value = data.aws_region.current.name }
  ]

  #  secret_vars = var.secret_vars

  tags = {
    app       = local.app
    env       = local.env
    service   = local.app
    team      = local.team
    Terraform = "True"
  }
}

resource "aws_service_discovery_http_namespace" "this" {
  name        = "${local.env}-${local.app}"
  description = "Cloudmap namespace for ${local.app} in ${local.env}"
  tags        = local.tags
}

resource "aws_security_group" "alb_sg" {
  name        = "${local.env}-${local.app}-alb-sg"
  description = "Allow http and https inbound traffic"
  vpc_id      = data.aws_vpc.selected.id

  ingress {
    description = "Allow http and https inbound traffic"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    # cidr_blocks = [data.aws_vpc.selected.cidr_block]
    security_groups = ["${module.ecs_task.security_group_id}"]
  }

  tags = local.tags
}

module "alb" {
  source  = "terraform-aws-modules/alb/aws"
  version = "~> 8.0"

  name = "${local.env}-${local.app}-alb"

  load_balancer_type = "application"

  idle_timeout = 600

  vpc_id                     = data.aws_vpc.selected.id
  subnets                    = data.aws_subnets.public_subnet.ids
  security_groups            = [aws_security_group.alb_sg.id]
  drop_invalid_header_fields = true

  https_listeners = [
    {
      port               = 443
      protocol           = "HTTPS"
      certificate_arn    = data.aws_acm_certificate.selected.arn
      ssl_policy         = "ELBSecurityPolicy-TLS13-1-2-2021-06"
      target_group_index = 0
    },
  ]

  target_groups = [
    {
      name             = "${local.env}-${local.app}-${local.app_port}"
      backend_protocol = "HTTP"
      backend_port     = local.app_port
      target_type      = "ip"
      health_check = {
        enabled  = true
        interval = 30
        path     = local.health_check
        matcher  = "200"
      }
    },
  ]

  tags = local.tags
}


module "ecs_task" {
  source  = "terraform-aws-modules/ecs/aws//modules/service"
  version = "5.2.2"

  name        = "${local.env}-${local.app}"
  cluster_arn = data.aws_ecs_cluster.selected.arn

  cpu    = local.task_cpu
  memory = local.task_memory

  desired_count = local.desired_count

  container_definitions = {
    (local.app) = {
      cpu       = local.app_cpu
      memory    = local.app_memory
      essential = true

      enable_autoscaling       = true
      autoscaling_min_capacity = 1
      autoscaling_max_capacity = 2
      autoscaling_policies     = {}

      image                    = "835407888179.dkr.ecr.${data.aws_region.current.name}.amazonaws.com/${data.aws_ecr_image.app_image.repository_name}:${data.aws_ecr_image.app_image.image_tag}"
      readonly_root_filesystem = false

      health_check = {
        retries = 10
        command = ["CMD-SHELL", "curl -f http://localhost:${local.app_port}${local.health_check} || exit 1"]
        timeout : 5
        interval : 10
      }

      port_mappings = [
        {
          name          = local.app
          containerPort = local.app_port
          hostPort      = local.app_port
          protocol      = "http"
        }
      ]

      environment = local.env_vars

    }
  }

  deployment_circuit_breaker = {
    enable   = true
    rollback = true
  }

  subnet_ids = data.aws_subnets.private_subnet.ids

  service_connect_configuration = {
    namespace = aws_service_discovery_http_namespace.this.arn
    service = {
      client_alias = {
        port     = local.app_port
        dns_name = "${local.env}-${local.app}"
      }
      port_name      = local.app
      discovery_name = local.app
    }
  }

  load_balancer = {
    service = {
      target_group_arn = element(module.alb.target_group_arns, 0)
      container_name   = local.app
      container_port   = local.app_port
    }
  }

  security_group_rules = {
    ingress_all = {
      type                     = "ingress"
      from_port                = local.app_port
      to_port                  = local.app_port
      protocol                 = "tcp"
      source_security_group_id = aws_security_group.alb_sg.id
    }
    egress_all = {
      type        = "egress"
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  tags = local.tags
}
