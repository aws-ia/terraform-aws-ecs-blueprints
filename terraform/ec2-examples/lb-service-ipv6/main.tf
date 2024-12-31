provider "aws" {
  region = local.region
}

locals {
  name   = "ecsdemo-frontend-ipv6"
  region = "us-west-2"

  container_port = 3000 # Container port is specific to this app example
  container_name = "ecsdemo-frontend"

  tags = {
    Blueprint  = local.name
    GithubRepo = "github.com/aws-ia/ecs-blueprints"
  }
}

################################################################################
# ECS Blueprint
################################################################################

module "ecs_service" {
  source  = "terraform-aws-modules/ecs/aws//modules/service"
  version = "~> 5.6"

  name          = local.name
  desired_count = 3
  cluster_arn   = data.aws_ecs_cluster.core_infra.arn

  # Task Definition
  enable_execute_command   = true
  requires_compatibilities = ["EC2"]
  capacity_provider_strategy = {
    default = {
      capacity_provider = "core-infra-ipv6" # needs to match name of capacity provider
      weight            = 1
      base              = 1
    }
  }

  container_definitions = {
    (local.container_name) = {
      image                    = "public.ecr.aws/aws-containers/ecsdemo-frontend"
      readonly_root_filesystem = false

      port_mappings = [
        {
          protocol      = "tcp",
          containerPort = local.container_port
        }
      ]

      environment = [
        {
          name  = "NODEJS_URL",
          value = "http://ecsdemo-backend.${data.aws_service_discovery_dns_namespace.this.name}:${local.container_port}"
        }
      ]
    }
  }

  service_registries = {
    registry_arn = aws_service_discovery_service.this.arn
  }

  load_balancer = {
    service = {
      target_group_arn = module.alb.target_groups["ecs-task"].arn
      container_name   = local.container_name
      container_port   = local.container_port
    }
  }

  subnet_ids = data.aws_subnets.private.ids
  security_group_rules = {
    alb_ingress = {
      type                     = "ingress"
      from_port                = local.container_port
      to_port                  = local.container_port
      protocol                 = "tcp"
      description              = "Service port"
      source_security_group_id = module.alb.security_group_id
    }
    egress_all_ipv4 = {
      type        = "egress"
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = ["0.0.0.0/0"]
    }
    egress_all_ipv6 = {
      type             = "egress"
      from_port        = 0
      to_port          = 0
      protocol         = "-1"
      ipv6_cidr_blocks = ["::/0"]
    }
  }




  tags = local.tags
}

resource "aws_service_discovery_service" "this" {
  name = local.name

  dns_config {
    namespace_id = data.aws_service_discovery_dns_namespace.this.id

    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    failure_threshold = 1
  }
}

module "alb" {
  source  = "terraform-aws-modules/alb/aws"
  version = "~> 9.0"

  name = local.name

  # For example only
  enable_deletion_protection = false

  vpc_id          = data.aws_vpc.vpc.id
  subnets         = data.aws_subnets.public.ids
  ip_address_type = "dualstack"
  security_group_ingress_rules = {
    all_http_ipv4 = {
      from_port   = 80
      to_port     = 80
      ip_protocol = "tcp"
      description = "HTTP web traffic"
      cidr_ipv4   = "0.0.0.0/0"
    }
    all_http_ipv6 = {
      from_port   = 8080
      to_port     = 8080
      ip_protocol = "tcp"
      description = "HTTP web traffic"
      cidr_ipv6   = "::/0"
    }
  }
  security_group_egress_rules = merge(
    { for subnet in data.aws_subnet.private_cidr : "${subnet.availability_zone}" => {
      ip_protocol = "-1"
      cidr_ipv4   = subnet.cidr_block
      }
    },
    { for subnet in data.aws_subnet.private_cidr : "${subnet.availability_zone}-ipv6" => {
      ip_protocol = "-1"
      cidr_ipv6   = subnet.ipv6_cidr_block
      }
    }
  )


  listeners = {
    http = {
      port     = "80"
      protocol = "HTTP"

      forward = {
        target_group_key = "ecs-task"
      }
    }
    http2 = {
      port     = "8080"
      protocol = "HTTP"

      forward = {
        target_group_key = "ecs-task-ipv6"
      }
    }
  }

  target_groups = {
    ecs-task = {
      backend_protocol = "HTTP"
      backend_port     = local.container_port
      target_type      = "ip"

      health_check = {
        enabled             = true
        healthy_threshold   = 5
        interval            = 30
        matcher             = "200-299"
        path                = "/"
        port                = "traffic-port"
        protocol            = "HTTP"
        timeout             = 5
        unhealthy_threshold = 2
      }

      # There's nothing to attach here in this definition. Instead,
      # ECS will attach the IPs of the tasks to this target group
      create_attachment = false
    }

    #this is just to show that due current limitations, ECS Targets are not registered on the ipv6 target group.
    #This is documented on https://docs.aws.amazon.com/AmazonECS/latest/developerguide/alb.html#alb-considerations
    #Consider the following when using Application Load Balancers with Amazon ECS:
    #Target group must have the IP address type set to IPv4.

    ecs-task-ipv6 = {
      backend_protocol = "HTTP"
      backend_port     = local.container_port
      target_type      = "ip"
      ip_address_type  = "ipv6"

      health_check = {
        enabled             = true
        healthy_threshold   = 5
        interval            = 30
        matcher             = "200-299"
        path                = "/"
        port                = "traffic-port"
        protocol            = "HTTP"
        timeout             = 5
        unhealthy_threshold = 2
      }

      # There's nothing to attach here in this definition. Instead,
      # ECS will attach the IPs of the tasks to this target group
      create_attachment = false
    }

  }

  tags = local.tags
}

################################################################################
# Supporting Resources
################################################################################

data "aws_vpc" "vpc" {
  filter {
    name   = "tag:Name"
    values = ["core-infra-ipv6"]
  }
}

data "aws_subnets" "public" {
  filter {
    name   = "tag:Name"
    values = ["core-infra-ipv6-public-*"]
  }
}

data "aws_subnets" "private" {
  filter {
    name   = "tag:Name"
    values = ["core-infra-ipv6-private-*"]
  }
}

data "aws_subnet" "private_cidr" {
  for_each = toset(data.aws_subnets.private.ids)
  id       = each.value
}

data "aws_ecs_cluster" "core_infra" {
  cluster_name = "core-infra-ipv6"
}

data "aws_service_discovery_dns_namespace" "this" {
  name = "default.${data.aws_ecs_cluster.core_infra.cluster_name}.local"
  type = "DNS_PRIVATE"
}
