variable "name_prefix" { type = string }
variable "vpc_id" { type = string }
variable "subnet_ids" { type = list(string) }
variable "allowed_sg_ids" { type = list(string) }
variable "tags" { type = map(string) }

resource "aws_efs_file_system" "this" {
  encrypted        = true
  performance_mode = "generalPurpose"
  throughput_mode  = "bursting"
  tags             = merge(var.tags, { Name = "${var.name_prefix}-efs" })
}

resource "aws_security_group" "efs" {
  name   = "${var.name_prefix}-efs"
  vpc_id = var.vpc_id
  tags   = merge(var.tags, { Name = "${var.name_prefix}-efs-sg" })
}

resource "aws_security_group_rule" "nfs" {
  count                    = length(var.allowed_sg_ids)
  type                     = "ingress"
  from_port                = 2049
  to_port                  = 2049
  protocol                 = "tcp"
  security_group_id        = aws_security_group.efs.id
  source_security_group_id = var.allowed_sg_ids[count.index]
}

resource "aws_security_group_rule" "efs_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  security_group_id = aws_security_group.efs.id
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_efs_mount_target" "this" {
  count           = length(var.subnet_ids)
  file_system_id  = aws_efs_file_system.this.id
  subnet_id       = var.subnet_ids[count.index]
  security_groups = [aws_security_group.efs.id]
}

output "file_system_id" { value = aws_efs_file_system.this.id }
output "security_group_id" { value = aws_security_group.efs.id }
