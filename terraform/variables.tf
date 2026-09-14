variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "name_prefix" {
  type    = string
  default = "agent-plane"
}

variable "vpc_cidr" {
  type    = string
  default = "10.80.0.0/16"
}

variable "image_uri" {
  type        = string
  description = "Full URI of the agent runtime image (ECR), including tag."
  default     = "111111111111.dkr.ecr.us-east-1.amazonaws.com/agent-plane/runtime:ci"
}

variable "alloy_image" {
  type    = string
  default = "grafana/alloy:v1.8.3"
}

variable "github_org" {
  type    = string
  default = "kachieze"
}

variable "github_repo" {
  type    = string
  default = "buzz-247-agents-graph"
}

variable "github_oidc_role_arn" {
  type        = string
  default     = ""
  description = "If empty, this stack creates the GitHub OIDC deploy role. Workflows still read vars.AWS_ROLE_ARN."
}

variable "github_auth_mode" {
  type    = string
  default = "app"
  validation {
    condition     = contains(["app", "pat"], var.github_auth_mode)
    error_message = "github_auth_mode must be app or pat."
  }
}

variable "relay_enabled" {
  type    = bool
  default = true
}

variable "relay_image" {
  type    = string
  default = "ghcr.io/block/buzz:desktop-v0.5.20"
}

variable "relay_wss_url" {
  type        = string
  default     = ""
  description = "Required when relay_enabled=false. When relay is in-stack, output ALB URL is used unless this is set."
}

variable "relay_hostname" {
  type    = string
  default = ""
}

variable "relay_acm_certificate_arn" {
  type    = string
  default = ""
}

variable "create_dns" {
  type    = bool
  default = false
}

variable "route53_zone_id" {
  type    = string
  default = ""
}

variable "relay_owner_pubkey" {
  type    = string
  default = ""
}

variable "grafana_otlp_endpoint" {
  type    = string
  default = ""
}

variable "agents" {
  description = "Map of agent id → service. Empty map still applies infra."
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
  default = {}
}

variable "create_secret_shells" {
  type    = bool
  default = true
}

variable "tags" {
  type = map(string)
  default = {
    Project = "buzz-247-agents-graph"
  }
}
