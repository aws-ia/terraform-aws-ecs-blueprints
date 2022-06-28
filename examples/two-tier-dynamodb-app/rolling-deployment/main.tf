provider "aws" {
  region = local.region
}

data "aws_availability_zones" "available" {}
data "aws_caller_identity" "id_current_account" {}

locals {
  name   = basename(path.cwd)
  region = "us-west-2"

  vpc_cidr = "10.0.0.0/16"
  azs      = slice(data.aws_availability_zones.available.names, 0, 3)

  tags = {
    Blueprint  = local.name
    GithubRepo = "github.com/aws-ia/terraform-aws-ecs-blueprints"
  }
}

################################################################################
# ECS Blueprint
################################################################################

module "ecs" {
  source  = "terraform-aws-modules/ecs/aws"
  version = "~> 4.0"

  cluster_name = local.name

  tags = local.tags
}

module "client_alb_security_group" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 4.0"

  name        = "${local.name}-client"
  description = "Security group for client application"
  vpc_id      = module.vpc.vpc_id

  ingress_rules       = ["http-80-tcp"]
  ingress_cidr_blocks = ["0.0.0.0/0"]

  egress_rules       = ["all-all"]
  egress_cidr_blocks = module.vpc.private_subnets_cidr_blocks

  tags = local.tags
}

module "client_alb" {
  source  = "terraform-aws-modules/alb/aws"
  version = "~> 7.0"

  name = "${local.name}-client"

  load_balancer_type = "application"

  vpc_id          = module.vpc.vpc_id
  subnets         = module.vpc.public_subnets
  security_groups = [module.client_alb_security_group.security_group_id]

  http_tcp_listeners = [
    {
      port               = 80
      protocol           = "HTTP"
      target_group_index = 0
    },
  ]

  target_groups = [
    {
      name_prefix      = "${local.name}-client-blue-"
      backend_protocol = "HTTP"
      backend_port     = 80
      target_type      = "ip"
      health_check = {
        path    = "/"
        port    = var.port_app_client
        matcher = "200-299"
      }
    },
  ]

  tags = local.tags
}

module "server_alb_security_group" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 4.0"

  name        = "${local.name}-client"
  description = "Security group for client application"
  vpc_id      = module.vpc.vpc_id

  ingress_with_source_security_group_id = [
    {
      rule                     = "http-80-tcp"
      source_security_group_id = module.client_alb_security_group.security_group_id
    },
  ]

  egress_rules       = ["all-all"]
  egress_cidr_blocks = module.vpc.private_subnets_cidr_blocks

  tags = local.tags
}

module "server_alb" {
  source  = "terraform-aws-modules/alb/aws"
  version = "~> 7.0"

  name = "${local.name}-server"

  load_balancer_type = "application"
  internal           = true

  vpc_id          = module.vpc.vpc_id
  subnets         = module.vpc.private_subnets
  security_groups = [module.server_alb_security_group.security_group_id]

  http_tcp_listeners = [
    {
      port               = 80
      protocol           = "HTTP"
      target_group_index = 0
    },
  ]

  target_groups = [
    {
      name_prefix      = "${local.name}-server-blue-"
      backend_protocol = "HTTP"
      backend_port     = 80
      target_type      = "ip"
      health_check = {
        path    = "/status"
        port    = var.port_app_server
        matcher = "200-299"
      }
    },
  ]

  tags = local.tags
}

# ------- ECS Role -------
module "ecs_role" {
  source = "./../../../modules/iam"

  create_ecs_role = true

  name               = var.iam_role_name["ecs"]
  name_ecs_task_role = var.iam_role_name["ecs_task_role"]
  dynamodb_table     = [module.assets_dynamodb_table.dynamodb_table_arn]
}

# ------- Creating a IAM Policy for role -------
module "ecs_role_policy" {
  source = "./../../../modules/iam"

  name      = "ecs-ecr-${local.name}"
  attach_to = module.ecs_role.name_role
}

# ------- Creating server ECR Repository to store Docker Images -------
module "server_ecr" {
  source  = "terraform-aws-modules/ecr/aws"
  version = "~> 1.0"

  repository_name = "${local.name}-server"

  repository_read_access_arns       = [module.ecs_role.arn_role]
  repository_read_write_access_arns = [module.devops_role.arn_role]

  tags = local.tags
}

# ------- Creating client ECR Repository to store Docker Images -------
module "client_ecr" {
  source  = "terraform-aws-modules/ecr/aws"
  version = "~> 1.0"

  repository_name = "${local.name}-client"

  repository_read_access_arns       = [module.ecs_role.arn_role]
  repository_read_write_access_arns = [module.devops_role.arn_role]

  tags = local.tags
}

resource "aws_cloudwatch_log_group" "client" {
  name              = "/ecs/task-definition-${var.ecs_service_name["client"]}"
  retention_in_days = 30
}

resource "aws_cloudwatch_log_group" "server" {
  name              = "/ecs/task-definition-${var.ecs_service_name["server"]}"
  retention_in_days = 30
}

# ------- Creating ECS Task Definition for the server -------
module "ecs_taks_definition_server" {
  source = "./../../../modules/ecs/task-definition"

  name                 = var.ecs_service_name["server"]
  container_name       = var.container_name["server"]
  execution_role       = module.ecs_role.arn_role
  task_role            = module.ecs_role.arn_role_ecs_task_role
  cpu                  = 256
  memory               = 512
  image                = module.server_ecr.repository_url
  region               = local.region
  container_port       = var.port_app_server
  cloudwatch_log_group = aws_cloudwatch_log_group.server.name
}

# ------- Creating ECS Task Definition for the client -------
module "ecs_taks_definition_client" {
  source = "./../../../modules/ecs/task-definition"

  name                 = var.ecs_service_name["client"]
  container_name       = var.container_name["client"]
  execution_role       = module.ecs_role.arn_role
  task_role            = module.ecs_role.arn_role_ecs_task_role
  cpu                  = 256
  memory               = 512
  image                = module.client_ecr.repository_url
  region               = local.region
  container_port       = var.port_app_client
  cloudwatch_log_group = aws_cloudwatch_log_group.client.name
}

# ------- Creating a server Security Group for ECS TASKS -------
module "client_task_security_group" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 4.0"

  name        = "${local.name}-client-task"
  description = "Security group for client task"
  vpc_id      = module.vpc.vpc_id

  ingress_with_source_security_group_id = [
    {
      rule                     = "http-80-tcp"
      source_security_group_id = module.client_alb_security_group.security_group_id
    },
  ]

  egress_rules = ["all-all"]

  tags = local.tags
}

module "server_task_security_group" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 4.0"

  name        = "${local.name}-server-task"
  description = "Security group for server task"
  vpc_id      = module.vpc.vpc_id

  ingress_with_source_security_group_id = [
    {
      from_port                = var.port_app_server
      to_port                  = var.port_app_server
      protocol                 = "tcp"
      source_security_group_id = module.server_alb_security_group.security_group_id
    },
  ]

  egress_rules = ["all-all"]

  tags = local.tags
}

# ------- Creating ECS Service server -------
module "ecs_service_server" {
  source = "./../../../modules/ecs/service"

  name            = var.ecs_service_name["server"]
  desired_count   = var.ecs_desired_tasks["server"]
  security_groups = [module.server_task_security_group.security_group_id]
  ecs_cluster_id  = module.ecs.cluster_id
  load_balancers = [{
    container_name   = var.container_name["server"]
    container_port   = var.port_app_server
    target_group_arn = element(module.server_alb.target_group_arns, 0)
  }]
  task_definition                    = module.ecs_taks_definition_server.task_definition_arn
  subnets                            = module.vpc.private_subnets
  deployment_maximum_percent         = var.deployment_maximum_percent["server"]
  deployment_minimum_healthy_percent = var.deployment_minimum_healthy_percent["server"]
  health_check_grace_period_seconds  = var.seconds_health_check_grace_period
  deployment_controller              = "ECS"

  tags = local.tags
}

# ------- Creating ECS Service client -------
module "ecs_service_client" {
  source = "./../../../modules/ecs/service"

  name            = var.ecs_service_name["client"]
  desired_count   = var.ecs_desired_tasks["client"]
  security_groups = [module.client_task_security_group.security_group_id]
  ecs_cluster_id  = module.ecs.cluster_id
  load_balancers = [{
    container_name   = var.container_name["client"]
    container_port   = var.port_app_client
    target_group_arn = element(module.client_alb.target_group_arns, 0)
  }]
  task_definition                    = module.ecs_taks_definition_client.task_definition_arn
  subnets                            = module.vpc.private_subnets
  deployment_maximum_percent         = var.deployment_maximum_percent["client"]
  deployment_minimum_healthy_percent = var.deployment_minimum_healthy_percent["client"]
  health_check_grace_period_seconds  = var.seconds_health_check_grace_period
  deployment_controller              = "ECS"

  tags = local.tags
}

# ------- Creating ECS Autoscaling policies for the server application -------
module "ecs_autoscaling_server" {
  source = "./../../../modules/ecs/autoscaling"

  service_name     = var.ecs_service_name["server"]
  cluster_name     = module.ecs.cluster_id
  min_capacity     = var.ecs_autoscaling_min_capacity["server"]
  max_capacity     = var.ecs_autoscaling_max_capacity["server"]
  cpu_threshold    = var.cpu_threshold["server"]
  memory_threshold = var.memory_threshold["server"]
}

# ------- Creating ECS Autoscaling policies for the client application -------
module "ecs_autoscaling_client" {
  source = "./../../../modules/ecs/autoscaling"

  service_name     = var.ecs_service_name["client"]
  cluster_name     = module.ecs.cluster_id
  min_capacity     = var.ecs_autoscaling_min_capacity["client"]
  max_capacity     = var.ecs_autoscaling_max_capacity["client"]
  cpu_threshold    = var.cpu_threshold["client"]
  memory_threshold = var.memory_threshold["client"]
}

# ------- CodePipeline -------

# ------- Creating Bucket to store CodePipeline artifacts -------
module "codepipeline_s3_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 3.0"

  bucket = "codepipeline-${local.region}-${random_id.this.hex}"
  acl    = "private"

  # For example only - please evaluate for your environment
  force_destroy = true

  attach_deny_insecure_transport_policy = true
  attach_require_latest_tls_policy      = true

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm = "AES256"
      }
    }
  }

  tags = local.tags
}

# ------- Creating IAM roles used during the pipeline excecution -------
module "devops_role" {
  source = "./../../../modules/iam"

  create_devops_role = true
  name               = var.iam_role_name["devops"]
}

# ------- Creating an IAM Policy for role -------
module "policy_devops_role" {
  source = "./../../../modules/iam"

  create_devops_policy = true

  name                = "devops-${local.name}"
  attach_to           = module.devops_role.name_role
  ecr_repositories    = [module.server_ecr.repository_arn, module.client_ecr.repository_arn]
  code_build_projects = [module.codebuild_client.project_arn, module.codebuild_server.project_arn]
}

# ------- Creating a SNS topic -------
module "sns" {
  source = "./../../../modules/sns"

  sns_name = "sns-${local.name}"
}

# ------- Creating the server CodeBuild project -------
module "codebuild_server" {
  source = "./codebuild"

  name                   = "codebuild-${local.name}-server"
  iam_role               = module.devops_role.arn_role
  region                 = local.region
  account_id             = data.aws_caller_identity.id_current_account.account_id
  ecr_repo_url           = module.server_ecr.repository_url
  folder_path            = var.folder_path_server
  buildspec_path         = var.buildspec_path
  task_definition_family = module.ecs_taks_definition_server.task_definition_family
  container_name         = var.container_name["server"]
  service_port           = var.port_app_server
  ecs_role               = var.iam_role_name["ecs"]
  ecs_task_role          = var.iam_role_name["ecs_task_role"]
  dynamodb_table_name    = module.assets_dynamodb_table.dynamodb_table_id
}

# ------- Creating the client CodeBuild project -------
module "codebuild_client" {
  source = "./codebuild"

  name                   = "codebuild-${local.name}-client"
  iam_role               = module.devops_role.arn_role
  region                 = local.region
  account_id             = data.aws_caller_identity.id_current_account.account_id
  ecr_repo_url           = module.client_ecr.repository_url
  folder_path            = var.folder_path_client
  buildspec_path         = var.buildspec_path
  task_definition_family = module.ecs_taks_definition_client.task_definition_family
  container_name         = var.container_name["client"]
  service_port           = var.port_app_client
  ecs_role               = var.iam_role_name["ecs"]
  server_alb_url         = module.server_alb.lb_dns_name
}

# ------- Creating CodePipeline -------
module "codepipeline" {
  source = "./codepipeline"

  name                     = "pipeline-${local.name}"
  pipe_role                = module.devops_role.arn_role
  s3_bucket                = module.codepipeline_s3_bucket.s3_bucket_id
  github_token             = var.github_token
  repo_owner               = var.repository_owner
  repo_name                = var.repository_name
  branch                   = var.repository_branch
  codebuild_project_server = module.codebuild_server.project_id
  codebuild_project_client = module.codebuild_client.project_id
  ecs_cluster_name         = module.ecs.cluster_id
  ecs_service_name_client  = var.ecs_service_name["client"]
  ecs_service_name_server  = var.ecs_service_name["server"]
  sns_topic                = module.sns.sns_arn
}

# ------- Creating Bucket to store assets accessed by the Back-end -------
module "assets_s3_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 3.0"

  bucket = "assets-${local.region}-${random_id.this.hex}"
  acl    = "private"

  # For example only - please evaluate for your environment
  force_destroy = true

  attach_deny_insecure_transport_policy = true
  attach_require_latest_tls_policy      = true

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm = "AES256"
      }
    }
  }

  tags = local.tags
}

# ------- Creating Dynamodb table by the Back-end -------
module "assets_dynamodb_table" {
  source  = "terraform-aws-modules/dynamodb-table/aws"
  version = "~> 2.0"

  name = "${local.name}-assets"

  tags = local.tags
}

################################################################################
# Supporting Resources
################################################################################

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 3.0"

  name = local.name
  cidr = local.vpc_cidr

  azs             = local.azs
  public_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k)]
  private_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 10)]

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  # Manage so we can name
  manage_default_network_acl    = true
  default_network_acl_tags      = { Name = "${local.name}-default" }
  manage_default_route_table    = true
  default_route_table_tags      = { Name = "${local.name}-default" }
  manage_default_security_group = true
  default_security_group_tags   = { Name = "${local.name}-default" }

  tags = local.tags
}

resource "random_id" "this" {
  byte_length = "2"
}
