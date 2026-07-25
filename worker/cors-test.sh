#!/usr/bin/env bash
# Diagnose the browser path: preflight + POST with Origin, headers only.
set -euo pipefail
W=https://feedloop.tryunloop.workers.dev
echo "== OPTIONS preflight (as the browser sends it) =="
curl -sS -o /dev/null -D - -X OPTIONS "$W/login" \
  -H "Origin: https://iamalisufyan.github.io" \
  -H "Access-Control-Request-Method: POST" \
  -H "Access-Control-Request-Headers: content-type" | grep -iE "^HTTP|access-control"
echo "== POST with Origin (bad creds, expect 401 + CORS headers) =="
curl -sS -o /dev/null -D - -X POST "$W/login" \
  -H "Origin: https://iamalisufyan.github.io" \
  -H "Content-Type: application/json" -d '{"email":"x","password":"y"}' \
  | grep -iE "^HTTP|access-control"
