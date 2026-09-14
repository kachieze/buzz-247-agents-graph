output "vpc_id" {
  value = module.network.vpc_id
}

output "private_subnet_ids" {
  value = module.network.private_subnet_ids
}

output "ecr_repository_url" {
  value = module.ecr.repository_url
}

output "efs_id" {
  value = module.efs.file_system_id
}

output "ecs_cluster_name" {
  value = module.ecs_cluster.cluster_name
}

output "relay_wss_url" {
  value = local.effective_relay_wss
}

output "relay_alb_dns" {
  value       = try(module.relay[0].alb_dns_name, null)
  description = "Set a CNAME to this when create_dns=false."
}

output "github_oidc_role_arn" {
  value = local.github_oidc_role_arn
}

output "agent_service_names" {
  value = { for k, m in module.agent_service : k => m.service_name }
}

output "secret_arns" {
  value     = module.secrets.secret_arns
  sensitive = true
}

output "agent_task_definition_examples" {
  value = { for k, m in module.agent_service : k => m.task_definition_json }
}

output "operator_put_secret_examples" {
  value = [
    "aws secretsmanager put-secret-value --secret-id agent-plane/alpha/nsec --secret-string 'nsec1…'",
    "aws secretsmanager put-secret-value --secret-id agent-plane/alpha/cursor --secret-string 'cursor_…'",
  ]
}
