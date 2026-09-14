# buzz-247-agents-graph

Cookie-cutter **ECS Fargate** plane for headless Buzz agents. One Docker image, N Fargate services (`desiredCount = 1`), harness **`buzz-acp`** spawning **`cursor-agent acp`**. Grafana Alloy sidecar. Optional in-stack Buzz relay (RDS + ElastiCache + S3 + ALB).

GitHub: https://github.com/kachieze/buzz-247-agents-graph

**Not this repo:** Buzz Desktop, GNOME, DCV, EC2 nests, Datadog, `pm2`, `src/agent.js` listeners, baking secrets into the image, or `terraform apply` from CI without an account.

## Runtime

```
Relay WS  →  buzz-acp  --stdio ACP-->  cursor-agent acp
                 |                           |
                 +--> buzz CLI               +--> MCP jail ($HOME)
                 +--> respawn ACP child      +--> git / gh / Playwright Chromium
```

PID 1 is `entrypoint.sh` → `exec buzz-acp`. ECS stop therefore signals the harness.

Pinned Buzz source tag (Dockerfile `ARG BUZZ_RELEASE`): **`desktop-v0.5.20`**. Relay image default: `ghcr.io/block/buzz:desktop-v0.5.20`. Override both when you promote a tag.

## Cost knobs (defaults)

| Item | Default | Why |
|------|---------|-----|
| NAT | **one** in AZ0 | Biggest always-on VPC cost |
| RDS | `db.t4g.micro`, single-AZ | Spec; raise only if the relay needs it |
| Redis | `cache.t4g.micro`, 1 node | Same |
| S3 gateway endpoint | on | Cuts NAT bytes to S3 |
| Agent task | 4 vCPU / 16 GiB | Playwright + Cursor; override per agent in the map |
| Cursor model | service-account default | Set `agents.<id>.cursor_model` to a cheaper slug when quality holds |

Do not run two tasks with one nsec (`desiredCount` stays 1).

## Identity lifecycle (operator)

1. Apply infra (`agents = {}` is valid). Record `relay_wss_url`.
2. On a **laptop**, join that WSS. Create the agent (Desktop or `buzz-admin generate-key`). Save nsec + pubkey.
3. If `BUZZ_REQUIRE_RELAY_MEMBERSHIP=true`, `buzz-admin add-member` with `BUZZ_RELAY_PRIVATE_KEY`.
4. Add channel membership so the agent is mentionable.
5. `aws secretsmanager put-secret-value` for nsec and `CURSOR_API_KEY`. Apply with the agent in `agents`. **No image rebuild.**
6. Wait until the ECS service is stable. **Stop Desktop ACP for that pubkey.** Two listeners on one key race mentions. Code cannot enforce a global singleton.

Desktop **Edit agent** does **not** change Fargate `BUZZ_ACP_RESPOND_TO`. Patch tfvars and restart the service.

## Secrets (never in git)

| Secret | Who |
|--------|-----|
| `agent-plane/<id>/nsec` → `BUZZ_PRIVATE_KEY` | per agent |
| `agent-plane/<id>/cursor` → `CURSOR_API_KEY` | per agent |
| optional `BUZZ_AUTH_TAG` | per agent; needed only for `buzz agents draft-create` |
| GitHub App id / installation / PEM **or** PAT | stack |
| Grafana Cloud instance id + token | stack |
| Relay private key, RDS password, S3 keys | if `relay_enabled` |

Terraform creates **empty secret shells**. Fill them:

```bash
aws secretsmanager put-secret-value --secret-id agent-plane/alpha/nsec --secret-string 'nsec1…'
aws secretsmanager put-secret-value --secret-id agent-plane/alpha/cursor --secret-string 'cursor_…'
```

CI must not print secret values. Task IAM is EFS-only. Execution role pulls Secrets Manager `agent-plane/*`.

## Terraform variables

| Variable | Default | Notes |
|----------|---------|-------|
| `aws_region` | `us-east-1` | |
| `name_prefix` | `agent-plane` | |
| `vpc_cidr` | `10.80.0.0/16` | New VPC, 2 AZs, 2 public + 2 private |
| `image_uri` | dummy CI URI | Full ECR URI including tag (deploy sets this from the pushed image) |
| `alloy_image` | `grafana/alloy:v1.8.3` | Sidecar |
| `github_org` / `github_repo` | `kachieze` / `buzz-247-agents-graph` | OIDC `sub` |
| `github_oidc_role_arn` | `""` | Empty → create role; workflows still use `vars.AWS_ROLE_ARN` |
| `github_auth_mode` | `app` | `app` or `pat` |
| `relay_enabled` | `true` | `false` → no RDS/Redis/ALB; set `relay_wss_url` |
| `relay_image` | `ghcr.io/block/buzz:desktop-v0.5.20` | |
| `relay_wss_url` | `""` | Required when relay is external |
| `relay_hostname` | `""` | Optional DNS name |
| `relay_acm_certificate_arn` | `""` | Empty → HTTP :80 only |
| `create_dns` / `route53_zone_id` | false / `""` | |
| `relay_owner_pubkey` | `""` | |
| `grafana_otlp_endpoint` | `""` | Grafana Cloud OTLP URL |
| `agents` | `{}` | See example tfvars |
| `create_secret_shells` | `true` | |

State: partial `backend "s3" {}`. Init with:

```bash
terraform -chdir=terraform init \
  -backend-config="bucket=YOUR_BUCKET" \
  -backend-config="key=agent-plane/terraform.tfstate" \
  -backend-config="region=us-east-1"
```

Local `terraform init -backend=false` is enough to **validate**.

## GitHub Actions

- `ci.yml`: fmt, tflint, validate (no AWS creds), MCP jail tests, `docker build`.
- `deploy.yml`: OIDC (`vars.AWS_ROLE_ARN`), push ECR, `terraform apply -var image_uri=…`. Supply remaining vars as `TF_VAR_*` repository variables. **Do not apply until an account exists.**

## Local checks (no AWS)

```bash
cd src/mcp && npm ci && npm test
terraform -chdir=terraform fmt -check -recursive
terraform -chdir=terraform init -backend=false
terraform -chdir=terraform validate
docker build -t agent-plane:local .
```

`docker compose --profile relay up` is optional and **not** production.

## MCP jail

Filesystem tools are rooted at `$HOME` (`/agents/<id>` on EFS). Paths such as `../beta` are rejected. Playwright is **not** an MCP tool; Cursor drives Chromium via shell.

## Observability

`awslogs` → `/agent-plane/<id>`. Alloy receives OTLP on `127.0.0.1:4317`. Add the CloudWatch datasource in Grafana Cloud for logs. Empty OTEL from `buzz-acp` is OK in v1.

## License

Apache-2.0
