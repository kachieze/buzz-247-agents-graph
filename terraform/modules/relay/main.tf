variable "name_prefix" { type = string }
variable "vpc_id" { type = string }
variable "public_subnet_ids" { type = list(string) }
variable "private_subnet_ids" { type = list(string) }
variable "relay_sg_id" { type = string }
variable "alb_sg_id" { type = string }
variable "cluster_arn" { type = string }
variable "execution_role_arn" { type = string }
variable "task_role_arn" { type = string }
variable "relay_image" { type = string }
variable "hostname" { type = string }
variable "acm_certificate_arn" { type = string }
variable "create_dns" { type = bool }
variable "route53_zone_id" { type = string }
variable "relay_owner_pubkey" { type = string }
variable "relay_private_key_arn" { type = string }
variable "rds_password_arn" { type = string }
variable "s3_access_key_arn" { type = string }
variable "s3_secret_key_arn" { type = string }
variable "tags" { type = map(string) }

data "aws_region" "current" {}

resource "random_password" "rds" {
  length  = 24
  special = false
}

resource "aws_secretsmanager_secret_version" "rds_seed" {
  count         = var.rds_password_arn != "" ? 1 : 0
  secret_id     = var.rds_password_arn
  secret_string = random_password.rds.result
  lifecycle {
    ignore_changes = [secret_string]
  }
}

resource "aws_db_subnet_group" "relay" {
  name       = "${var.name_prefix}-relay"
  subnet_ids = var.private_subnet_ids
  tags       = var.tags
}

resource "aws_security_group" "rds" {
  name   = "${var.name_prefix}-rds"
  vpc_id = var.vpc_id
  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [var.relay_sg_id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = var.tags
}

resource "aws_db_instance" "relay" {
  identifier             = "${var.name_prefix}-pg"
  engine                 = "postgres"
  engine_version         = "16"
  instance_class         = "db.t4g.micro"
  allocated_storage      = 20
  db_name                = "buzz"
  username               = "buzz"
  password               = random_password.rds.result
  db_subnet_group_name   = aws_db_subnet_group.relay.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  skip_final_snapshot    = true
  publicly_accessible    = false
  multi_az               = false
  storage_encrypted      = true
  tags                   = var.tags
}

resource "aws_elasticache_subnet_group" "relay" {
  name       = "${var.name_prefix}-redis"
  subnet_ids = var.private_subnet_ids
}

resource "aws_security_group" "redis" {
  name   = "${var.name_prefix}-redis"
  vpc_id = var.vpc_id
  ingress {
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [var.relay_sg_id]
  }
  tags = var.tags
}

resource "aws_elasticache_cluster" "relay" {
  cluster_id           = "${var.name_prefix}-redis"
  engine               = "redis"
  node_type            = "cache.t4g.micro"
  num_cache_nodes      = 1
  parameter_group_name = "default.redis7"
  port                 = 6379
  subnet_group_name    = aws_elasticache_subnet_group.relay.name
  security_group_ids   = [aws_security_group.redis.id]
  tags                 = var.tags
}

resource "aws_s3_bucket" "media" {
  bucket_prefix = "${var.name_prefix}-media-"
  tags          = var.tags
}

resource "aws_s3_bucket_public_access_block" "media" {
  bucket                  = aws_s3_bucket.media.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_iam_user" "s3" {
  name = "${var.name_prefix}-blossom"
  tags = var.tags
}

resource "aws_iam_access_key" "s3" {
  user = aws_iam_user.s3.name
}

resource "aws_iam_user_policy" "s3" {
  name = "blossom"
  user = aws_iam_user.s3.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]
      Resource = [aws_s3_bucket.media.arn, "${aws_s3_bucket.media.arn}/*"]
    }]
  })
}

resource "aws_secretsmanager_secret_version" "s3_access" {
  count         = var.s3_access_key_arn != "" ? 1 : 0
  secret_id     = var.s3_access_key_arn
  secret_string = aws_iam_access_key.s3.id
}

resource "aws_secretsmanager_secret_version" "s3_secret" {
  count         = var.s3_secret_key_arn != "" ? 1 : 0
  secret_id     = var.s3_secret_key_arn
  secret_string = aws_iam_access_key.s3.secret
}

resource "aws_lb" "relay" {
  name               = "${var.name_prefix}-relay"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.alb_sg_id]
  subnets            = var.public_subnet_ids
  tags               = var.tags
}

resource "aws_lb_target_group" "relay" {
  name        = "${var.name_prefix}-relay"
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"
  health_check {
    path = "/_liveness"
    port = "8080"
  }
  tags = var.tags
}

resource "aws_lb_listener" "https" {
  count             = var.acm_certificate_arn != "" ? 1 : 0
  load_balancer_arn = aws_lb.relay.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.acm_certificate_arn
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.relay.arn
  }
}

resource "aws_lb_listener" "http_redirect" {
  count             = var.acm_certificate_arn != "" ? 1 : 0
  load_balancer_arn = aws_lb.relay.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_listener" "http_forward" {
  count             = var.acm_certificate_arn == "" ? 1 : 0
  load_balancer_arn = aws_lb.relay.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.relay.arn
  }
}

resource "aws_route53_record" "relay" {
  count   = var.create_dns && var.route53_zone_id != "" && var.hostname != "" ? 1 : 0
  zone_id = var.route53_zone_id
  name    = var.hostname
  type    = "A"
  alias {
    name                   = aws_lb.relay.dns_name
    zone_id                = aws_lb.relay.zone_id
    evaluate_target_health = true
  }
}

resource "aws_cloudwatch_log_group" "relay" {
  name              = "/agent-plane/relay"
  retention_in_days = 14
  tags              = var.tags
}

resource "aws_ecs_task_definition" "relay" {
  family                   = "${var.name_prefix}-relay"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 1024
  memory                   = 2048
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = var.task_role_arn
  container_definitions = jsonencode([{
    name      = "relay"
    image     = var.relay_image
    essential = true
    portMappings = [
      { containerPort = 3000, protocol = "tcp" },
      { containerPort = 8080, protocol = "tcp" }
    ]
    environment = [
      { name = "BUZZ_BIND_ADDR", value = "0.0.0.0:3000" },
      { name = "BUZZ_HEALTH_PORT", value = "8080" },
      { name = "BUZZ_AUTO_MIGRATE", value = "true" },
      { name = "BUZZ_REQUIRE_RELAY_MEMBERSHIP", value = "true" },
      { name = "RELAY_OWNER_PUBKEY", value = var.relay_owner_pubkey },
      { name = "RELAY_URL", value = var.hostname != "" ? "wss://${var.hostname}" : "ws://${aws_lb.relay.dns_name}" },
      { name = "DATABASE_URL", value = "postgres://buzz:${random_password.rds.result}@${aws_db_instance.relay.address}:5432/buzz" },
      { name = "REDIS_URL", value = "redis://${aws_elasticache_cluster.relay.cache_nodes[0].address}:6379" },
      { name = "BUZZ_S3_BUCKET", value = aws_s3_bucket.media.bucket },
      { name = "BUZZ_S3_REGION", value = data.aws_region.current.name },
      { name = "BUZZ_S3_ENDPOINT", value = "https://s3.${data.aws_region.current.name}.amazonaws.com" },
    ]
    secrets = concat(
      var.relay_private_key_arn != "" ? [{ name = "BUZZ_RELAY_PRIVATE_KEY", valueFrom = var.relay_private_key_arn }] : [],
      var.s3_access_key_arn != "" ? [{ name = "BUZZ_S3_ACCESS_KEY", valueFrom = var.s3_access_key_arn }] : [],
      var.s3_secret_key_arn != "" ? [{ name = "BUZZ_S3_SECRET_KEY", valueFrom = var.s3_secret_key_arn }] : [],
    )
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.relay.name
        awslogs-region        = data.aws_region.current.name
        awslogs-stream-prefix = "relay"
      }
    }
  }])
}

resource "aws_ecs_service" "relay" {
  name             = "${var.name_prefix}-relay"
  cluster          = var.cluster_arn
  task_definition  = aws_ecs_task_definition.relay.arn
  desired_count    = 1
  launch_type      = "FARGATE"
  platform_version = "1.4.0"
  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.relay_sg_id]
    assign_public_ip = false
  }
  load_balancer {
    target_group_arn = aws_lb_target_group.relay.arn
    container_name   = "relay"
    container_port   = 3000
  }
  tags = var.tags
}

output "alb_dns_name" { value = aws_lb.relay.dns_name }
output "rds_address" { value = aws_db_instance.relay.address }
output "media_bucket" { value = aws_s3_bucket.media.bucket }
