variable "name_prefix" { type = string }
variable "github_org" { type = string }
variable "github_repo" { type = string }
variable "create_github_oidc" { type = bool }
variable "ecr_repository_arn" { type = string }
variable "efs_file_system_arn" { type = string }

# Per-agent execution/task roles. Each execution role may GetSecretValue only
# on that agent's secrets (+ shared GitHub/Grafana), never sibling nsecs.
variable "agents" {
  type = map(object({
    secret_arns      = list(string)
    access_point_arn = string
  }))
}

variable "relay_secret_arns" {
  type    = list(string)
  default = []
}

variable "relay_enabled" {
  type    = bool
  default = false
}

variable "tags" { type = map(string) }

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

data "aws_iam_policy_document" "ecs_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.name

  # Known ARN shapes — avoid depending on ecs_cluster module (ordering).
  pass_role_arns = compact(concat(
    [for id, _ in var.agents : "arn:aws:iam::${local.account_id}:role/${var.name_prefix}-${id}-exec"],
    [for id, _ in var.agents : "arn:aws:iam::${local.account_id}:role/${var.name_prefix}-${id}-task"],
    var.relay_enabled ? [
      "arn:aws:iam::${local.account_id}:role/${var.name_prefix}-relay-exec",
      "arn:aws:iam::${local.account_id}:role/${var.name_prefix}-relay-task",
    ] : [],
  ))

  ecs_service_arns = compact(concat(
    [for id, _ in var.agents : "arn:aws:ecs:${local.region}:${local.account_id}:service/${var.name_prefix}/${var.name_prefix}-${id}"],
    var.relay_enabled ? ["arn:aws:ecs:${local.region}:${local.account_id}:service/${var.name_prefix}/${var.name_prefix}-relay"] : [],
  ))

  ecs_task_definition_arn = "arn:aws:ecs:${local.region}:${local.account_id}:task-definition/${var.name_prefix}-*:*"
}

# ---------------------------------------------------------------------------
# Per-agent execution roles (O1) + task roles (O2 EFS AP + O5 Exec)
# ---------------------------------------------------------------------------

resource "aws_iam_role" "agent_execution" {
  for_each           = var.agents
  name               = "${var.name_prefix}-${each.key}-exec"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
  tags               = merge(var.tags, { Agent = each.key })
}

resource "aws_iam_role_policy_attachment" "agent_execution_managed" {
  for_each   = var.agents
  role       = aws_iam_role.agent_execution[each.key].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "agent_execution_secrets" {
  for_each = var.agents
  name     = "secrets"
  role     = aws_iam_role.agent_execution[each.key].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = length(each.value.secret_arns) > 0 ? each.value.secret_arns : ["arn:aws:secretsmanager:${local.region}:${local.account_id}:secret:${var.name_prefix}/${each.key}/*"]
    }]
  })
}

resource "aws_iam_role" "agent_task" {
  for_each           = var.agents
  name               = "${var.name_prefix}-${each.key}-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
  tags               = merge(var.tags, { Agent = each.key })
}

resource "aws_iam_role_policy" "agent_efs" {
  for_each = var.agents
  name     = "efs-client"
  role     = aws_iam_role.agent_task[each.key].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "EfsDescribeMountTargets"
        Effect   = "Allow"
        Action   = ["elasticfilesystem:DescribeMountTargets"]
        Resource = var.efs_file_system_arn
      },
      {
        Sid    = "EfsClientMountViaAccessPoint"
        Effect = "Allow"
        Action = [
          "elasticfilesystem:ClientMount",
          "elasticfilesystem:ClientWrite",
        ]
        Resource = var.efs_file_system_arn
        Condition = {
          StringEquals = {
            "elasticfilesystem:AccessPointArn" = each.value.access_point_arn
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "agent_ecs_exec" {
  for_each = var.agents
  name     = "ecs-exec"
  role     = aws_iam_role.agent_task[each.key].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ssmmessages:CreateControlChannel",
        "ssmmessages:CreateDataChannel",
        "ssmmessages:OpenControlChannel",
        "ssmmessages:OpenDataChannel"
      ]
      Resource = "*"
    }]
  })
}

# ---------------------------------------------------------------------------
# Relay execution + task roles
# ---------------------------------------------------------------------------

resource "aws_iam_role" "relay_execution" {
  count              = var.relay_enabled ? 1 : 0
  name               = "${var.name_prefix}-relay-exec"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "relay_execution_managed" {
  count      = var.relay_enabled ? 1 : 0
  role       = aws_iam_role.relay_execution[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "relay_execution_secrets" {
  count = var.relay_enabled ? 1 : 0
  name  = "secrets"
  role  = aws_iam_role.relay_execution[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = length(var.relay_secret_arns) > 0 ? var.relay_secret_arns : ["arn:aws:secretsmanager:${local.region}:${local.account_id}:secret:${var.name_prefix}/relay/*"]
    }]
  })
}

resource "aws_iam_role" "relay_task" {
  count              = var.relay_enabled ? 1 : 0
  name               = "${var.name_prefix}-relay-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
  tags               = var.tags
}

# S3 object policy is attached in the relay module (bucket ARN known there).

# ---------------------------------------------------------------------------
# GitHub Actions OIDC deploy role (O4)
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "github_oidc_assume" {
  count = var.create_github_oidc ? 1 : 0
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github[0].arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:${var.github_org}/${var.github_repo}:ref:refs/heads/main",
      ]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_openid_connect_provider" "github" {
  count          = var.create_github_oidc ? 1 : 0
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  # GitHub Actions OIDC thumbprints (AWS still requires the list; values are
  # the documented GitHub leaf + intermediate cert fingerprints).
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd",
  ]
  tags = var.tags
}

resource "aws_iam_role" "github_oidc" {
  count              = var.create_github_oidc ? 1 : 0
  name               = "${var.name_prefix}-gha"
  assume_role_policy = data.aws_iam_policy_document.github_oidc_assume[0].json
  tags               = var.tags
}

resource "aws_iam_role_policy" "github_oidc" {
  count = var.create_github_oidc ? 1 : 0
  name  = "deploy"
  role  = aws_iam_role.github_oidc[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          Effect   = "Allow"
          Action   = ["ecr:GetAuthorizationToken"]
          Resource = "*"
        },
        {
          Effect = "Allow"
          Action = [
            "ecr:BatchCheckLayerAvailability",
            "ecr:CompleteLayerUpload",
            "ecr:InitiateLayerUpload",
            "ecr:PutImage",
            "ecr:UploadLayerPart",
            "ecr:BatchGetImage"
          ]
          Resource = var.ecr_repository_arn
        },
        {
          Effect = "Allow"
          Action = [
            "ecs:DescribeServices",
            "ecs:DescribeTaskDefinition",
          ]
          Resource = "*"
        },
        {
          Effect   = "Allow"
          Action   = ["ecs:RegisterTaskDefinition"]
          Resource = local.ecs_task_definition_arn
        },
      ],
      length(local.ecs_service_arns) > 0 ? [
        {
          Effect   = "Allow"
          Action   = ["ecs:UpdateService"]
          Resource = local.ecs_service_arns
        }
      ] : [],
      length(local.pass_role_arns) > 0 ? [
        {
          Effect   = "Allow"
          Action   = ["iam:PassRole"]
          Resource = local.pass_role_arns
          Condition = {
            StringEquals = {
              "iam:PassedToService" = "ecs-tasks.amazonaws.com"
            }
          }
        }
      ] : [],
    )
  })
}

output "agent_execution_role_arns" {
  value = { for k, r in aws_iam_role.agent_execution : k => r.arn }
}

output "agent_task_role_arns" {
  value = { for k, r in aws_iam_role.agent_task : k => r.arn }
}

output "relay_execution_role_arn" {
  value = try(aws_iam_role.relay_execution[0].arn, "")
}

output "relay_task_role_arn" {
  value = try(aws_iam_role.relay_task[0].arn, "")
}

output "relay_task_role_name" {
  value = try(aws_iam_role.relay_task[0].name, "")
}

output "github_oidc_role_arn" {
  value = try(aws_iam_role.github_oidc[0].arn, "")
}
