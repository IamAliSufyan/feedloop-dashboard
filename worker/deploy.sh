#!/usr/bin/env bash
# Deploy the Feedloop worker to Cloudflare. One command, idempotent.
#
# Needs (one time, from Ali):
#   ~/.config/unloop-feedloop/cloudflare.env   CLOUDFLARE_API_TOKEN=... (Edit Workers template)
#   ~/.config/unloop-feedloop/github-pat.env   GITHUB_PAT=github_pat_... (fine-grained,
#                                              unloop-app only, Contents R/W, 1 year)
# Generates on first run (never printed to chat):
#   ~/.config/unloop-feedloop/dashboard-login.txt   the email + password Ali signs in with
set -euo pipefail
cd "$(dirname "$0")"

CONF=~/.config/unloop-feedloop
# shellcheck disable=SC1091
set -a; source "$CONF/cloudflare.env"; source "$CONF/github-pat.env"; set +a
: "${CLOUDFLARE_API_TOKEN:?missing in cloudflare.env}"
: "${GITHUB_PAT:?missing in github-pat.env}"
export CLOUDFLARE_API_TOKEN

LOGIN_EMAIL="${LOGIN_EMAIL:-azkar554a@gmail.com}"

# Create login credentials on first deploy; reuse after that.
if [ ! -f "$CONF/dashboard-login.txt" ]; then
  PASSWORD=$(python3 -c "import secrets,string; a=string.ascii_letters+string.digits; print('-'.join(''.join(secrets.choice(a) for _ in range(5)) for _ in range(4)))")
  printf "Feedloop dashboard login\nemail: %s\npassword: %s\n" "$LOGIN_EMAIL" "$PASSWORD" > "$CONF/dashboard-login.txt"
  chmod 600 "$CONF/dashboard-login.txt"
  echo "credentials written to $CONF/dashboard-login.txt"
else
  PASSWORD=$(awk '/^password: /{print $2}' "$CONF/dashboard-login.txt")
  LOGIN_EMAIL=$(awk '/^email: /{print $2}' "$CONF/dashboard-login.txt")
fi

# Salted PBKDF2 hash of the password (what the worker stores).
LOGIN_HASH=$(PW="$PASSWORD" python3 - <<'PY'
import hashlib, os, secrets
pw = os.environ["PW"].encode()
salt = secrets.token_bytes(16)
dk = hashlib.pbkdf2_hmac("sha256", pw, salt, 100000)
print(salt.hex() + ":" + dk.hex())
PY
)
SESSION_SECRET_FILE="$CONF/session-secret.txt"
if [ ! -f "$SESSION_SECRET_FILE" ]; then
  python3 -c "import secrets; print(secrets.token_hex(32))" > "$SESSION_SECRET_FILE"
  chmod 600 "$SESSION_SECRET_FILE"
fi
SESSION_SECRET=$(cat "$SESSION_SECRET_FILE")

echo "== deploy worker =="
npx --yes wrangler@latest deploy

echo "== push secrets =="
printf '%s' "$LOGIN_EMAIL"    | npx --yes wrangler@latest secret put LOGIN_EMAIL
printf '%s' "$LOGIN_HASH"     | npx --yes wrangler@latest secret put LOGIN_HASH
printf '%s' "$SESSION_SECRET" | npx --yes wrangler@latest secret put SESSION_SECRET
printf '%s' "$GITHUB_PAT"     | npx --yes wrangler@latest secret put GITHUB_PAT

echo "== done. worker URL =="
npx --yes wrangler@latest deployments list 2>/dev/null | head -3 || true
echo "(URL is https://feedloop.<your-subdomain>.workers.dev)"
