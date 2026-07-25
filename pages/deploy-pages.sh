#!/usr/bin/env bash
# Deploy the dashboard + its API to Cloudflare Pages (same-origin, no CORS,
# and NOT on workers.dev which some networks block).
#
# Reads the same credential files as the worker deploy.
set -euo pipefail
cd "$(dirname "$0")"

CONF=~/.config/unloop-feedloop
# shellcheck disable=SC1090
set -a; source "$CONF/cloudflare.env"; source "$CONF/github-pat.env"; set +a
: "${CLOUDFLARE_API_TOKEN:?missing}"; : "${GITHUB_PAT:?missing}"
export CLOUDFLARE_API_TOKEN

# This machine's router DNS fails on some Cloudflare hostnames; force public
# resolvers for the wrangler process only (no system settings touched).
export NODE_OPTIONS="--require $PWD/dns-fix.cjs${NODE_OPTIONS:+ $NODE_OPTIONS}"

PROJECT=feedloop
EMAIL=$(awk '/^email: /{print $2}' "$CONF/dashboard-login.txt")
PASSWORD=$(awk '/^password: /{print $2}' "$CONF/dashboard-login.txt")
SESSION_SECRET=$(cat "$CONF/session-secret.txt")
LOGIN_HASH=$(PW="$PASSWORD" python3 - <<'PY'
import hashlib, os, secrets
salt = secrets.token_bytes(16)
print(salt.hex() + ":" + hashlib.pbkdf2_hmac("sha256", os.environ["PW"].encode(), salt, 100000).hex())
PY
)

echo "== create project (ok if it already exists) =="
npx --yes wrangler@latest pages project create "$PROJECT" --production-branch main 2>&1 | tail -2 || true

echo "== set secrets on production =="
for pair in "LOGIN_EMAIL=$EMAIL" "LOGIN_HASH=$LOGIN_HASH" "SESSION_SECRET=$SESSION_SECRET" "GITHUB_PAT=$GITHUB_PAT"; do
  name="${pair%%=*}"; value="${pair#*=}"
  printf '%s' "$value" | npx --yes wrangler@latest pages secret put "$name" --project-name "$PROJECT" >/dev/null 2>&1 \
    && echo "  set $name" || echo "  FAILED $name"
done

echo "== deploy =="
npx --yes wrangler@latest pages deploy . --project-name "$PROJECT" --branch main --commit-dirty=true 2>&1 | tail -6
