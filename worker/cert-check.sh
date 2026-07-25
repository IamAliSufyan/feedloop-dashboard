#!/usr/bin/env bash
# Verify the worker's TLS cert is valid and the host is reachable repeatedly.
set -euo pipefail
H=feedloop.tryunloop.workers.dev
echo "== TLS certificate =="
echo | openssl s_client -connect "$H:443" -servername "$H" 2>/dev/null \
  | openssl x509 -noout -subject -issuer -dates 2>/dev/null || echo "TLS HANDSHAKE FAILED"
echo "== 5 consecutive requests =="
for i in 1 2 3 4 5; do
  curl -sS -o /dev/null -m 10 -w "  try $i: HTTP %{http_code} in %{time_total}s\n" "https://$H/" || echo "  try $i: FAILED"
done
