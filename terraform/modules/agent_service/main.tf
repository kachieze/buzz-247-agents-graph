variable "name_prefix" { type = string }
variable "agent_id" { type = string }
variable "efs_subdir" { type = string }
variable "cpu" { type = number }
variable "memory" { type = number }
variable "ephemeral_storage" { type = number }
variable "respond_to" { type = string }
variable "cursor_model" { type = string }
variable "image_uri" { type = string }
variable "alloy_image" { type = string }
variable "alloy_config" { type = string }
variable "cluster_arn" { type = string }
variable "subnet_ids" { type = list(string) }
variable "security_group_ids" { type = list(string) }
variable "execution_role_arn" { type = string }
variable "task_role_arn" { type = string }
variable "efs_id" { type = string }
variable "relay_wss_url" { type = string }
variable "github_auth_mode" { type = string }
variable "grafana_otlp_endpoint" { type = string }
variable "nsec_secret_arn" { type = string }
variable "cursor_secret_arn" { type = string }
variable "auth_tag_secret_arn" { type = string }
variable "github_app_id_arn" { type = string }
variable "github_install_id_arn" { type = string }
variable "github_app_pem_arn" { type = string }
variable "github_pat_arn" { type = string }
variable "grafana_instance_arn" { type = string }
variable "grafana_token_arn" { type = string }
variable "tags" { type = map(string) }

resource "aws_cloudwatch_log_group" "agent" {
  name              = "/agent-plane/${var.agent_id}"
  retention_in_days = 14
  tags              = var.tags
}

locals {
  github_secrets = var.github_auth_mode == "app" ? [
    { name = "GITHUB_APP_ID", valueFrom = var.github_app_id_arn },
    { name = "GITHUB_APP_INSTALLATION_ID", valueFrom = var.github_install_id_arn },
    { name = "GITHUB_APP_PRIVATE_KEY", valueFrom = var.github_app_pem_arn },
    ] : [
    { name = "GITHUB_PAT", valueFrom = var.github_pat_arn },
  ]
  auth_tag_secrets = var.auth_tag_secret_arn != "" ? [
    { name = "BUZZ_AUTH_TAG", valueFrom = var.auth_tag_secret_arn }
  ] : []
  grafana_secrets = var.grafana_token_arn != "" ? [
    { name = "GRAFANA_CLOUD_INSTANCE_ID", valueFrom = var.grafana_instance_arn },
    { name = "GRAFANA_CLOUD_API_TOKEN", valueFrom = var.grafana_token_arn },
  ] : []
}

resource "aws_ecs_task_definition" "agent" {
  family                   = "${var.name_prefix}-${var.agent_id}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = var.task_role_arn
  ephemeral_storage {
    size_in_gib = var.ephemeral_storage
  }

  volume {
    name = "agent-efs"
    efs_volume_configuration {
      file_system_id     = var.efs_id
      transit_encryption = "ENABLED"
      root_directory     = "/"
    }
  }

  container_definitions = jsonencode(concat([
    {
      name      = "agent"
      image     = var.image_uri
      essential = true
      user      = "0"
      linuxParameters = {
        initProcessEnabled = true
      }
      environment = concat(
        [
          { name = "AGENT_ID", value = var.efs_subdir },
          { name = "EFS_ROOT", value = "/agents" },
          { name = "BUZZ_RELAY_URL", value = var.relay_wss_url },
          { name = "BUZZ_ACP_RESPOND_TO", value = var.respond_to },
          { name = "BUZZ_ACP_AGENT_COMMAND", value = "cursor-agent" },
          { name = "BUZZ_ACP_AGENT_ARGS", value = "acp" },
          { name = "BUZZ_ACP_AGENTS", value = "1" },
          { name = "BUZZ_ACP_IDLE_TIMEOUT", value = "900" },
          { name = "BUZZ_ACP_MAX_TURN_DURATION", value = "7200" },
          { name = "BUZZ_ACP_MCP_COMMAND", value = "/opt/mcp/server.mjs" },
          { name = "MCP_FS_ROOT", value = "/agents/${var.efs_subdir}" },
          { name = "GITHUB_AUTH_MODE", value = var.github_auth_mode },
          { name = "OTEL_EXPORTER_OTLP_ENDPOINT", value = "http://127.0.0.1:4317" },
        ],
        var.cursor_model != "" ? [{ name = "CURSOR_MODEL", value = var.cursor_model }] : [],
        var.grafana_otlp_endpoint != "" ? [{ name = "GRAFANA_CLOUD_OTLP_ENDPOINT", value = var.grafana_otlp_endpoint }] : [],
      )
      secrets = concat(
        [
          { name = "BUZZ_PRIVATE_KEY", valueFrom = var.nsec_secret_arn },
          { name = "CURSOR_API_KEY", valueFrom = var.cursor_secret_arn },
        ],
        local.github_secrets,
        local.auth_tag_secrets,
      )
      mountPoints = [{
        sourceVolume  = "agent-efs"
        containerPath = "/agents"
        readOnly      = false
      }]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.agent.name
          awslogs-region        = data.aws_region.current.name
          awslogs-stream-prefix = "agent"
        }
      }
    },
    {
      name      = "alloy"
      image     = var.alloy_image
      essential = false
      environment = concat(
        [
          { name = "ALLOY_CONFIG", value = var.alloy_config },
        ],
        var.grafana_otlp_endpoint != "" ? [{ name = "GRAFANA_CLOUD_OTLP_ENDPOINT", value = var.grafana_otlp_endpoint }] : [],
      )
      secrets    = local.grafana_secrets
      entryPoint = ["/bin/sh", "-c"]
      command    = ["printf '%s\\n' \"$ALLOY_CONFIG\" > /tmp/config.alloy && exec /bin/alloy run --storage.path=/tmp/alloy --config.file=/tmp/config.alloy"]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.agent.name
          awslogs-region        = data.aws_region.current.name
          awslogs-stream-prefix = "alloy"
        }
      }
    }
  ]))
}

data "aws_region" "current" {}

resource "aws_ecs_service" "agent" {
  name                   = "${var.name_prefix}-${var.agent_id}"
  cluster                = var.cluster_arn
  task_definition        = aws_ecs_task_definition.agent.arn
  desired_count          = 1
  launch_type            = "FARGATE"
  platform_version       = "1.4.0"
  enable_execute_command = true
  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = var.security_group_ids
    assign_public_ip = false
  }
  tags = var.tags
}

output "service_name" { value = aws_ecs_service.agent.name }
output "task_definition_arn" { value = aws_ecs_task_definition.agent.arn }
output "task_definition_json" { value = aws_ecs_task_definition.agent.container_definitions }
