variable "name_prefix" { type = string }
variable "tags" { type = map(string) }

resource "aws_ecr_repository" "agent" {
  name                 = "${var.name_prefix}/runtime"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration { scan_on_push = true }
  tags = var.tags
}

resource "aws_ecr_lifecycle_policy" "agent" {
  repository = aws_ecr_repository.agent.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 20"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 20
      }
      action = { type = "expire" }
    }]
  })
}

output "repository_url" { value = aws_ecr_repository.agent.repository_url }
output "repository_arn" { value = aws_ecr_repository.agent.arn }
