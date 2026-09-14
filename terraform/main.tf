locals {
  github_oidc_role_arn = var.github_oidc_role_arn != "" ? var.github_oidc_role_arn : module.iam.github_oidc_role_arn
  relay_tls            = var.relay_hostname != "" || var.relay_acm_certificate_arn != ""
  relay_host           = var.relay_hostname != "" ? var.relay_hostname : try(module.relay[0].alb_dns_name, "pending")
  relay_scheme         = local.relay_tls ? "wss" : "ws"
  in_stack_wss         = var.relay_enabled ? "${local.relay_scheme}://${local.relay_host}" : var.relay_wss_url
  effective_relay_wss  = var.relay_wss_url != "" ? var.relay_wss_url : local.in_stack_wss
}

check "relay_wss_url_required" {
  assert {
    condition     = var.relay_enabled || trimspace(var.relay_wss_url) != ""
    error_message = "relay_wss_url must be a non-empty string when relay_enabled is false."
  }
}

module "network" {
  source      = "./modules/network"
  name_prefix = var.name_prefix
  vpc_cidr    = var.vpc_cidr
  tags        = var.tags
}

module "ecr" {
  source      = "./modules/ecr"
  name_prefix = var.name_prefix
  tags        = var.tags
}

module "efs" {
  source         = "./modules/efs"
  name_prefix    = var.name_prefix
  vpc_id         = module.network.vpc_id
  subnet_ids     = module.network.private_subnet_ids
  allowed_sg_ids = compact(concat([module.network.agent_sg_id], var.relay_enabled ? [module.network.relay_sg_id] : []))
  tags           = var.tags
}

module "iam" {
  source             = "./modules/iam"
  name_prefix        = var.name_prefix
  github_org         = var.github_org
  github_repo        = var.github_repo
  create_github_oidc = var.github_oidc_role_arn == ""
  ecr_repository_arn = module.ecr.repository_arn
  secret_arns        = module.secrets.secret_arns_list
  tags               = var.tags
}

module "secrets" {
  source               = "./modules/secrets"
  name_prefix          = var.name_prefix
  agents               = var.agents
  create_secret_shells = var.create_secret_shells
  relay_enabled        = var.relay_enabled
  github_auth_mode     = var.github_auth_mode
  tags                 = var.tags
}

module "ecs_cluster" {
  source      = "./modules/ecs_cluster"
  name_prefix = var.name_prefix
  tags        = var.tags
}

module "grafana" {
  source = "./modules/grafana"
}

module "agent_service" {
  source   = "./modules/agent_service"
  for_each = var.agents

  name_prefix           = var.name_prefix
  agent_id              = each.key
  efs_subdir            = each.value.efs_subdir
  cpu                   = each.value.cpu
  memory                = each.value.memory
  ephemeral_storage     = each.value.ephemeral_storage
  respond_to            = each.value.respond_to
  cursor_model          = try(each.value.cursor_model, "")
  image_uri             = var.image_uri
  alloy_image           = var.alloy_image
  alloy_config          = module.grafana.alloy_config
  cluster_arn           = module.ecs_cluster.cluster_arn
  subnet_ids            = module.network.private_subnet_ids
  security_group_ids    = [module.network.agent_sg_id]
  execution_role_arn    = module.iam.execution_role_arn
  task_role_arn         = module.iam.agent_task_role_arn
  efs_id                = module.efs.file_system_id
  relay_wss_url         = local.effective_relay_wss
  github_auth_mode      = var.github_auth_mode
  grafana_otlp_endpoint = var.grafana_otlp_endpoint
  nsec_secret_arn       = module.secrets.agent_nsec_arns[each.key]
  cursor_secret_arn     = module.secrets.agent_cursor_arns[each.key]
  auth_tag_secret_arn   = lookup(module.secrets.agent_auth_tag_arns, each.key, "")
  github_app_id_arn     = module.secrets.github_app_id_arn
  github_install_id_arn = module.secrets.github_install_id_arn
  github_app_pem_arn    = module.secrets.github_app_pem_arn
  github_pat_arn        = module.secrets.github_pat_arn
  grafana_instance_arn  = module.secrets.grafana_instance_arn
  grafana_token_arn     = module.secrets.grafana_token_arn
  tags                  = var.tags
}

module "relay" {
  count  = var.relay_enabled ? 1 : 0
  source = "./modules/relay"

  name_prefix           = var.name_prefix
  vpc_id                = module.network.vpc_id
  public_subnet_ids     = module.network.public_subnet_ids
  private_subnet_ids    = module.network.private_subnet_ids
  relay_sg_id           = module.network.relay_sg_id
  alb_sg_id             = module.network.alb_sg_id
  cluster_arn           = module.ecs_cluster.cluster_arn
  execution_role_arn    = module.iam.execution_role_arn
  task_role_arn         = module.iam.relay_task_role_arn
  relay_image           = var.relay_image
  hostname              = var.relay_hostname
  acm_certificate_arn   = var.relay_acm_certificate_arn
  create_dns            = var.create_dns
  route53_zone_id       = var.route53_zone_id
  relay_owner_pubkey    = var.relay_owner_pubkey
  relay_private_key_arn = module.secrets.relay_private_key_arn
  rds_password_arn      = module.secrets.rds_password_arn
  s3_access_key_arn     = module.secrets.s3_access_key_arn
  s3_secret_key_arn     = module.secrets.s3_secret_key_arn
  tags                  = var.tags
}
