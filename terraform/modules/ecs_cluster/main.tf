variable "name_prefix" { type = string }
variable "tags" { type = map(string) }

resource "aws_ecs_cluster" "this" {
  name = var.name_prefix
  setting {
    name  = "containerInsights"
    value = "enabled"
  }
  tags = var.tags
}

resource "aws_cloudwatch_log_group" "cluster" {
  name              = "/${var.name_prefix}/cluster"
  retention_in_days = 14
  tags              = var.tags
}

output "cluster_arn" { value = aws_ecs_cluster.this.arn }
output "cluster_name" { value = aws_ecs_cluster.this.name }
