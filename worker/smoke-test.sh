#!/usr/bin/env bash
# End-to-end smoke test of the deployed worker. Prints statuses only.
set -euo pipefail
W="https://feedloop.tryunloop.workers.dev"
CONF=~/.config/unloop-feedloop

echo "1) health:"
curl -sS "$W/" | head -c 120; echo

echo "2) login with WRONG password (expect 401):"
curl -sS -o /dev/null -w "   HTTP %{http_code}\n" -X POST "$W/login" \
  -H "Content-Type: application/json" -d '{"email":"azkar554a@gmail.com","password":"wrong"}'

echo "3) login with real credentials (expect 200):"
EMAIL=$(awk '/^email: /{print $2}' "$CONF/dashboard-login.txt")
PASS=$(awk '/^password: /{print $2}' "$CONF/dashboard-login.txt")
RESP=$(curl -sS -X POST "$W/login" -H "Content-Type: application/json" \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PASS\"}")
TOKEN=$(printf '%s' "$RESP" | python3 -c "import json,sys; print(json.load(sys.stdin).get('token',''))")
[ -n "$TOKEN" ] && echo "   HTTP 200, got session token (not shown)" || { echo "   LOGIN FAILED: $RESP"; exit 1; }

echo "4) proxy: list queue via /gh (expect file names):"
curl -sS -H "Authorization: Bearer $TOKEN" \
  "$W/gh/repos/IamAliSufyan/unloop-app/contents/docs/marketing/feedloop/content/queue?ref=main" \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print('   ' + ', '.join(x['name'] for x in d[:5]) + ' ...')"

echo "5) proxy scope guard: path outside feedloop (expect 403):"
curl -sS -o /dev/null -w "   HTTP %{http_code}\n" -H "Authorization: Bearer $TOKEN" \
  "$W/gh/repos/IamAliSufyan/unloop-app/contents/Unloop/App/UnloopApp.swift?ref=main"

echo "ALL CHECKS DONE"
