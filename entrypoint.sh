#!/usr/bin/env bash
# PID 1: EFS home, optional GitHub App token loop, exec buzz-acp.
set -euo pipefail

AGENT_ID="${AGENT_ID:?AGENT_ID is required}"
EFS_ROOT="${EFS_ROOT:-/agents}"
HOME_DIR="${EFS_ROOT}/${AGENT_ID}"
RUNTIME_USER="${RUNTIME_USER:-agent}"

if [[ "$(id -u)" -eq 0 ]]; then
  install -d -o "${RUNTIME_USER}" -g "${RUNTIME_USER}" -m 0750 "${HOME_DIR}"
  exec gosu "${RUNTIME_USER}" "$0" "$@"
fi

install -d -m 0750 "${HOME_DIR}"
export HOME="${HOME_DIR}"
export XDG_CONFIG_HOME="${HOME_DIR}/.config"
export XDG_CACHE_HOME="${HOME_DIR}/.cache"
mkdir -p "${XDG_CONFIG_HOME}" "${XDG_CACHE_HOME}" "${HOME_DIR}/.local/bin"
cd "${HOME}"

if [[ "${GITHUB_AUTH_MODE:-app}" == "app" ]]; then
  /usr/local/bin/github-token-refresh.sh &
elif [[ "${GITHUB_AUTH_MODE:-}" == "pat" ]]; then
  if [[ -n "${GITHUB_PAT:-}" ]]; then
    export GH_TOKEN="${GITHUB_PAT}"
    export GITHUB_TOKEN="${GITHUB_PAT}"
  fi
fi

export BUZZ_ACP_AGENT_COMMAND="${BUZZ_ACP_AGENT_COMMAND:-cursor-agent}"
export BUZZ_ACP_AGENT_ARGS="${BUZZ_ACP_AGENT_ARGS:-acp}"
export BUZZ_ACP_AGENTS="${BUZZ_ACP_AGENTS:-1}"
export BUZZ_ACP_MCP_COMMAND="${BUZZ_ACP_MCP_COMMAND:-/opt/mcp/server.mjs}"
export BUZZ_ACP_RESPOND_TO="${BUZZ_ACP_RESPOND_TO:-anyone}"
export BUZZ_ACP_IDLE_TIMEOUT="${BUZZ_ACP_IDLE_TIMEOUT:-900}"
export BUZZ_ACP_MAX_TURN_DURATION="${BUZZ_ACP_MAX_TURN_DURATION:-7200}"

exec buzz-acp
