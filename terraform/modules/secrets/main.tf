# Secret *shells* only — values never live in git.
# Fill with: aws secretsmanager put-secret-value

variable "name_prefix" { type = string }
variable "agents" {
  type = map(object({
    secret_name_nsec     = string
    efs_subdir           = string
    cpu                  = optional(number, 4096)
    memory               = optional(number, 16384)
    respond_to           = optional(string, "anyone")
    ephemeral_storage    = optional(number, 60)
    secret_name_cursor   = optional(string)
    secret_name_auth_tag = optional(string)
    cursor_model         = optional(string)
  }))
}
variable "create_secret_shells" { type = bool }
variable "relay_enabled" { type = bool }
variable "github_auth_mode" { type = string }
# 0 = throwaway lab only (immediate deletion). Real keys: >= 7 (O6).
variable "secret_recovery_window_days" {
  type    = number
  default = 7
}
variable "tags" { type = map(string) }

locals {
  agent_cursor_names = {
    for id, a in var.agents :
    id => coalesce(try(a.secret_name_cursor, null), "${var.name_prefix}/${id}/cursor")
  }
  agent_auth_tag_names = {
    for id, a in var.agents :
    id => a.secret_name_auth_tag
    if try(a.secret_name_auth_tag, null) != null && try(a.secret_name_auth_tag, "") != ""
  }
  recovery = var.secret_recovery_window_days
}

resource "aws_secretsmanager_secret" "agent_nsec" {
  for_each                = var.create_secret_shells ? var.agents : {}
  name                    = each.value.secret_name_nsec
  recovery_window_in_days = local.recovery
  tags                    = merge(var.tags, { Agent = each.key, Kind = "nsec" })
}

resource "aws_secretsmanager_secret" "agent_cursor" {
  for_each                = var.create_secret_shells ? var.agents : {}
  name                    = local.agent_cursor_names[each.key]
  recovery_window_in_days = local.recovery
  tags                    = merge(var.tags, { Agent = each.key, Kind = "cursor" })
}

resource "aws_secretsmanager_secret" "agent_auth_tag" {
  for_each                = var.create_secret_shells ? local.agent_auth_tag_names : {}
  name                    = each.value
  recovery_window_in_days = local.recovery
  tags                    = merge(var.tags, { Agent = each.key, Kind = "auth_tag" })
}

resource "aws_secretsmanager_secret" "github_app_id" {
  count                   = var.create_secret_shells && var.github_auth_mode == "app" ? 1 : 0
  name                    = "${var.name_prefix}/github/app-id"
  recovery_window_in_days = local.recovery
  tags                    = var.tags
}

resource "aws_secretsmanager_secret" "github_install_id" {
  count                   = var.create_secret_shells && var.github_auth_mode == "app" ? 1 : 0
  name                    = "${var.name_prefix}/github/installation-id"
  recovery_window_in_days = local.recovery
  tags                    = var.tags
}

resource "aws_secretsmanager_secret" "github_app_pem" {
  count                   = var.create_secret_shells && var.github_auth_mode == "app" ? 1 : 0
  name                    = "${var.name_prefix}/github/app-private-key"
  recovery_window_in_days = local.recovery
  tags                    = var.tags
}

resource "aws_secretsmanager_secret" "github_pat" {
  count                   = var.create_secret_shells && var.github_auth_mode == "pat" ? 1 : 0
  name                    = "${var.name_prefix}/github/pat"
  recovery_window_in_days = local.recovery
  tags                    = var.tags
}

resource "aws_secretsmanager_secret" "grafana_instance" {
  count                   = var.create_secret_shells ? 1 : 0
  name                    = "${var.name_prefix}/grafana/instance-id"
  recovery_window_in_days = local.recovery
  tags                    = var.tags
}

resource "aws_secretsmanager_secret" "grafana_token" {
  count                   = var.create_secret_shells ? 1 : 0
  name                    = "${var.name_prefix}/grafana/api-token"
  recovery_window_in_days = local.recovery
  tags                    = var.tags
}

resource "aws_secretsmanager_secret" "relay_private_key" {
  count                   = var.create_secret_shells && var.relay_enabled ? 1 : 0
  name                    = "${var.name_prefix}/relay/private-key"
  recovery_window_in_days = local.recovery
  tags                    = var.tags
}

# Full postgres URL (not bare password) — injected as DATABASE_URL via valueFrom (O3).
resource "aws_secretsmanager_secret" "database_url" {
  count                   = var.create_secret_shells && var.relay_enabled ? 1 : 0
  name                    = "${var.name_prefix}/relay/database-url"
  recovery_window_in_days = local.recovery
  tags                    = var.tags
}

resource "aws_secretsmanager_secret" "s3_access_key" {
  count                   = var.create_secret_shells && var.relay_enabled ? 1 : 0
  name                    = "${var.name_prefix}/relay/s3-access-key"
  recovery_window_in_days = local.recovery
  tags                    = var.tags
}

resource "aws_secretsmanager_secret" "s3_secret_key" {
  count                   = var.create_secret_shells && var.relay_enabled ? 1 : 0
  name                    = "${var.name_prefix}/relay/s3-secret-key"
  recovery_window_in_days = local.recovery
  tags                    = var.tags
}

data "aws_secretsmanager_secret" "agent_nsec" {
  for_each = var.create_secret_shells ? {} : var.agents
  name     = each.value.secret_name_nsec
}

data "aws_secretsmanager_secret" "agent_cursor" {
  for_each = var.create_secret_shells ? {} : var.agents
  name     = local.agent_cursor_names[each.key]
}

data "aws_secretsmanager_secret" "agent_auth_tag" {
  for_each = var.create_secret_shells ? {} : local.agent_auth_tag_names
  name     = each.value
}

data "aws_secretsmanager_secret" "github_app_id" {
  count = var.create_secret_shells || var.github_auth_mode != "app" ? 0 : 1
  name  = "${var.name_prefix}/github/app-id"
}

data "aws_secretsmanager_secret" "github_install_id" {
  count = var.create_secret_shells || var.github_auth_mode != "app" ? 0 : 1
  name  = "${var.name_prefix}/github/installation-id"
}

data "aws_secretsmanager_secret" "github_app_pem" {
  count = var.create_secret_shells || var.github_auth_mode != "app" ? 0 : 1
  name  = "${var.name_prefix}/github/app-private-key"
}

data "aws_secretsmanager_secret" "github_pat" {
  count = var.create_secret_shells || var.github_auth_mode != "pat" ? 0 : 1
  name  = "${var.name_prefix}/github/pat"
}

data "aws_secretsmanager_secret" "grafana_instance" {
  count = var.create_secret_shells ? 0 : 1
  name  = "${var.name_prefix}/grafana/instance-id"
}

data "aws_secretsmanager_secret" "grafana_token" {
  count = var.create_secret_shells ? 0 : 1
  name  = "${var.name_prefix}/grafana/api-token"
}

data "aws_secretsmanager_secret" "relay_private_key" {
  count = var.create_secret_shells || !var.relay_enabled ? 0 : 1
  name  = "${var.name_prefix}/relay/private-key"
}

data "aws_secretsmanager_secret" "database_url" {
  count = var.create_secret_shells || !var.relay_enabled ? 0 : 1
  name  = "${var.name_prefix}/relay/database-url"
}

data "aws_secretsmanager_secret" "s3_access_key" {
  count = var.create_secret_shells || !var.relay_enabled ? 0 : 1
  name  = "${var.name_prefix}/relay/s3-access-key"
}

data "aws_secretsmanager_secret" "s3_secret_key" {
  count = var.create_secret_shells || !var.relay_enabled ? 0 : 1
  name  = "${var.name_prefix}/relay/s3-secret-key"
}

locals {
  agent_nsec_arns = var.create_secret_shells ? {
    for k, s in aws_secretsmanager_secret.agent_nsec : k => s.arn
    } : {
    for k, s in data.aws_secretsmanager_secret.agent_nsec : k => s.arn
  }
  agent_cursor_arns = var.create_secret_shells ? {
    for k, s in aws_secretsmanager_secret.agent_cursor : k => s.arn
    } : {
    for k, s in data.aws_secretsmanager_secret.agent_cursor : k => s.arn
  }
  agent_auth_tag_arns = var.create_secret_shells ? {
    for k, s in aws_secretsmanager_secret.agent_auth_tag : k => s.arn
    } : {
    for k, s in data.aws_secretsmanager_secret.agent_auth_tag : k => s.arn
  }

  github_app_id_arn     = try(aws_secretsmanager_secret.github_app_id[0].arn, try(data.aws_secretsmanager_secret.github_app_id[0].arn, ""))
  github_install_id_arn = try(aws_secretsmanager_secret.github_install_id[0].arn, try(data.aws_secretsmanager_secret.github_install_id[0].arn, ""))
  github_app_pem_arn    = try(aws_secretsmanager_secret.github_app_pem[0].arn, try(data.aws_secretsmanager_secret.github_app_pem[0].arn, ""))
  github_pat_arn        = try(aws_secretsmanager_secret.github_pat[0].arn, try(data.aws_secretsmanager_secret.github_pat[0].arn, ""))
  grafana_instance_arn  = try(aws_secretsmanager_secret.grafana_instance[0].arn, try(data.aws_secretsmanager_secret.grafana_instance[0].arn, ""))
  grafana_token_arn     = try(aws_secretsmanager_secret.grafana_token[0].arn, try(data.aws_secretsmanager_secret.grafana_token[0].arn, ""))
  relay_private_key_arn = try(aws_secretsmanager_secret.relay_private_key[0].arn, try(data.aws_secretsmanager_secret.relay_private_key[0].arn, ""))
  database_url_arn      = try(aws_secretsmanager_secret.database_url[0].arn, try(data.aws_secretsmanager_secret.database_url[0].arn, ""))
  s3_access_key_arn     = try(aws_secretsmanager_secret.s3_access_key[0].arn, try(data.aws_secretsmanager_secret.s3_access_key[0].arn, ""))
  s3_secret_key_arn     = try(aws_secretsmanager_secret.s3_secret_key[0].arn, try(data.aws_secretsmanager_secret.s3_secret_key[0].arn, ""))

  secret_arns = compact(concat(
    values(local.agent_nsec_arns),
    values(local.agent_cursor_arns),
    values(local.agent_auth_tag_arns),
    [
      local.github_app_id_arn,
      local.github_install_id_arn,
      local.github_app_pem_arn,
      local.github_pat_arn,
      local.grafana_instance_arn,
      local.grafana_token_arn,
      local.relay_private_key_arn,
      local.database_url_arn,
      local.s3_access_key_arn,
      local.s3_secret_key_arn,
    ]
  ))

  relay_secret_arns = compact([
    local.relay_private_key_arn,
    local.database_url_arn,
    local.s3_access_key_arn,
    local.s3_secret_key_arn,
  ])

  shared_stack_secret_arns = compact([
    local.github_app_id_arn,
    local.github_install_id_arn,
    local.github_app_pem_arn,
    local.github_pat_arn,
    local.grafana_instance_arn,
    local.grafana_token_arn,
  ])
}

output "agent_nsec_arns" { value = local.agent_nsec_arns }
output "agent_cursor_arns" { value = local.agent_cursor_arns }
output "agent_auth_tag_arns" { value = local.agent_auth_tag_arns }
output "github_app_id_arn" { value = local.github_app_id_arn }
output "github_install_id_arn" { value = local.github_install_id_arn }
output "github_app_pem_arn" { value = local.github_app_pem_arn }
output "github_pat_arn" { value = local.github_pat_arn }
output "grafana_instance_arn" { value = local.grafana_instance_arn }
output "grafana_token_arn" { value = local.grafana_token_arn }
output "relay_private_key_arn" { value = local.relay_private_key_arn }
output "database_url_arn" { value = local.database_url_arn }
output "s3_access_key_arn" { value = local.s3_access_key_arn }
output "s3_secret_key_arn" { value = local.s3_secret_key_arn }
output "secret_arns" { value = local.secret_arns }
output "secret_arns_list" { value = local.secret_arns }
output "relay_secret_arns" { value = local.relay_secret_arns }
output "shared_stack_secret_arns" { value = local.shared_stack_secret_arns }
