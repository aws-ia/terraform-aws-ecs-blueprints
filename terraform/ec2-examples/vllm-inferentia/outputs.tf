################################################################################
# Cluster
################################################################################

output "cluster_arn" {
  description = "ARN that identifies the ECS cluster"
  value       = module.ecs_cluster.arn
}

################################################################################
# Load Balancer
################################################################################

output "load_balancer_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.vllm.dns_name
}

output "load_balancer_arn" {
  description = "ARN of the Application Load Balancer"
  value       = aws_lb.vllm.arn
}

output "target_group_arn" {
  description = "ARN of the Target Group"
  value       = aws_lb_target_group.vllm.arn
}

################################################################################
# ECS Service
################################################################################

output "ecs_service_name" {
  description = "Name of the ECS service"
  value       = aws_ecs_service.neuronx_vllm.name
}

output "ecs_service_task_definition" {
  description = "Task definition ARN for the ECS service"
  value       = aws_ecs_service.neuronx_vllm.task_definition
}

################################################################################
# Autoscaling
################################################################################

output "autoscaling_group_arn" {
  description = "ARN of the Autoscaling Group"
  value       = module.autoscaling.autoscaling_group_arn
}

################################################################################
# Networking
################################################################################

output "security_group_id" {
  description = "ID of the security group used by the ALB and ECS service"
  value       = module.autoscaling_sg.security_group_id
}

output "subnets" {
  description = "List of private subnet IDs used by ECS and the ALB"
  value       = data.aws_subnets.private.ids
}
