#!/usr/bin/env bash
# Render a human-readable ECS task-def JSON example from terraform output (optional).
set -euo pipefail
echo "Use: terraform -chdir=terraform output -json agent_task_definition_examples" >&2
terraform -chdir="$(dirname "$0")/../terraform" output -json agent_task_definition_examples 2>/dev/null || true
