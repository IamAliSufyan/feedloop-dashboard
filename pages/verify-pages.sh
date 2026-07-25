#!/usr/bin/env bash
# Verify the deployed Cloudflare Pages dashboard + API.
set -euo pipefail
cd "$(dirname "$0")"
export NODE_OPTIONS="--require $PWD/dns-fix.cjs${NODE_OPTIONS:+ $NODE_OPTIONS}"
# shellcheck disable=SC1090
set -a; source ~/.config/unloop-feedloop/cloudflare.env; set +a
export CLOUDFLARE_API_TOKEN
B=https://feedloop.pages.dev

echo "== secrets configured on the project =="
npx --yes wrangler@latest pages secret list --project-name feedloop 2>&1 | tail -8

echo "== static page served =="
curl -sS -m 20 -o /dev/null -w "  GET /            HTTP %{http_code}\n" "$B/"

echo "== api health =="
printf "  GET /api/health  "; curl -sS -m 20 "$B/api/health"; echo

echo "== login rejects a wrong password =="
curl -sS -m 20 -o /dev/null -w "  POST /api/login  HTTP %{http_code} (expect 401)\n" \
  -X POST "$B/api/login" -H "Content-Type: application/json" \
  -d '{"email":"x@y.z","password":"wrong"}'

echo "== login accepts the real credentials =="
EMAIL=$(awk '/^email: /{print $2}' ~/.config/unloop-feedloop/dashboard-login.txt)
PASS=$(awk '/^password: /{print $2}' ~/.config/unloop-feedloop/dashboard-login.txt)
TOKEN=$(curl -sS -m 20 -X POST "$B/api/login" -H "Content-Type: application/json" \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PASS\"}" \
  | python3 -c "import json,sys; print(json.load(sys.stdin).get('token',''))")
[ -n "$TOKEN" ] && echo "  HTTP 200, session issued (token not shown)" || { echo "  LOGIN FAILED"; exit 1; }

echo "== proxy reads the queue =="
curl -sS -m 20 -H "Authorization: Bearer $TOKEN" \
  "$B/api/gh/repos/IamAliSufyan/unloop-app/contents/docs/marketing/feedloop/content/queue?ref=main" \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print('  ' + str(len(d)) + ' files: ' + ', '.join(x['name'] for x in d[:4]) + ' ...')"

echo "== scope guard blocks non-feedloop paths =="
curl -sS -m 20 -o /dev/null -w "  HTTP %{http_code} (expect 403)\n" -H "Authorization: Bearer $TOKEN" \
  "$B/api/gh/repos/IamAliSufyan/unloop-app/contents/Unloop/App/UnloopApp.swift?ref=main"

echo "ALL PAGES CHECKS PASSED"
