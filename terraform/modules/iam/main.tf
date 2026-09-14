variable "name_prefix" { type = string }
variable "github_org" { type = string }
variable "github_repo" { type = string }
variable "create_github_oidc" { type = bool }
variable "ecr_repository_arn" { type = string }
variable "secret_arns" { type = list(string) }
variable "tags" { type = map(string) }

data "aws_iam_policy_document" "ecs_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "execution" {
  name               = "${var.name_prefix}-exec"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "execution_managed" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "execution_secrets" {
  name = "secrets"
  role = aws_iam_role.execution.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = length(var.secret_arns) > 0 ? var.secret_arns : ["arn:aws:secretsmanager:*:*:secret:agent-plane/*"]
    }]
  })
}

resource "aws_iam_role" "agent_task" {
  name               = "${var.name_prefix}-agent-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy" "agent_efs" {
  name = "efs-client"
  role = aws_iam_role.agent_task.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "elasticfilesystem:ClientMount",
        "elasticfilesystem:ClientWrite",
        "elasticfilesystem:ClientRootAccess",
        "elasticfilesystem:DescribeMountTargets"
      ]
      Resource = "*"
    }]
  })
}

resource "aws_iam_role" "relay_task" {
  name               = "${var.name_prefix}-relay-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy" "relay_s3" {
  name = "blossom-s3"
  role = aws_iam_role.relay_task.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]
      Resource = ["*"]
    }]
  })
}

data "aws_iam_policy_document" "github_oidc_assume" {
  count = var.create_github_oidc ? 1 : 0
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github[0].arn]
    }
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_org}/${var.github_repo}:*"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_openid_connect_provider" "github" {
  count           = var.create_github_oidc ? 1 : 0
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["ffffffffffffffffffffffffffffffffffffffff"]
  tags            = var.tags
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
    Statement = [
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
          "ecs:UpdateService",
          "ecs:DescribeServices",
          "ecs:DescribeTaskDefinition",
          "ecs:RegisterTaskDefinition",
          "iam:PassRole"
        ]
        Resource = "*"
      }
    ]
  })
}

output "execution_role_arn" { value = aws_iam_role.execution.arn }
output "agent_task_role_arn" { value = aws_iam_role.agent_task.arn }
output "relay_task_role_arn" { value = aws_iam_role.relay_task.arn }
output "github_oidc_role_arn" { value = try(aws_iam_role.github_oidc[0].arn, "") }
