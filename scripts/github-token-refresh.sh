#!/usr/bin/env bash
# Mint a GitHub App installation token every 50 minutes (tokens last 1 hour).
# Writes /tmp/gh_token and a git credential helper.
set -euo pipefail

TOKEN_FILE="${GH_TOKEN_FILE:-/tmp/gh_token}"

need() { [[ -n "${!1:-}" ]] || { echo "missing $1" >&2; exit 1; }; }
need GITHUB_APP_ID
need GITHUB_APP_INSTALLATION_ID
need GITHUB_APP_PRIVATE_KEY

b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }

mint() {
  local now iat exp header payload sig jwt
  now="$(date +%s)"
  iat=$((now - 30))
  exp=$((now + 540))
  header="$(printf '{"alg":"RS256","typ":"JWT"}' | b64url)"
  payload="$(printf '{"iat":%s,"exp":%s,"iss":%s}' "${iat}" "${exp}" "${GITHUB_APP_ID}" | b64url)"
  local pem
  pem="$(mktemp)"
  printf '%s\n' "${GITHUB_APP_PRIVATE_KEY}" >"${pem}"
  sig="$(printf '%s' "${header}.${payload}" | openssl dgst -sha256 -sign "${pem}" -binary | b64url)"
  rm -f "${pem}"
  jwt="${header}.${payload}.${sig}"
  curl -fsS -X POST \
    -H "Authorization: Bearer ${jwt}" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/app/installations/${GITHUB_APP_INSTALLATION_ID}/access_tokens" \
    | jq -r '.token'
}

git_helper() {
  cat >/tmp/git-gh-helper.sh <<'EOF'
#!/bin/sh
if [ "$1" = get ]; then
  echo "username=x-access-token"
  echo "password=$(cat /tmp/gh_token)"
fi
EOF
  chmod 0700 /tmp/git-gh-helper.sh
  git config --global credential.helper "/tmp/git-gh-helper.sh"
}

git_helper

while true; do
  token="$(mint)"
  printf '%s' "${token}" >"${TOKEN_FILE}"
  chmod 0600 "${TOKEN_FILE}"
  export GH_TOKEN="${token}"
  export GITHUB_TOKEN="${token}"
  if command -v gh >/dev/null 2>&1; then
    printf '%s\n' "${token}" | gh auth login --hostname github.com --with-token >/dev/null 2>&1 || true
    gh auth setup-git >/dev/null 2>&1 || true
  fi
  sleep 3000
done
