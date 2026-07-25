#!/usr/bin/env bash
# One-time: register the workers.dev subdomain for the account.
# Usage: register-subdomain.sh <account_id> <subdomain>
set -euo pipefail
# shellcheck disable=SC1090
set -a; source ~/.config/unloop-feedloop/cloudflare.env; set +a
curl -sS -X PUT "https://api.cloudflare.com/client/v4/accounts/$1/workers/subdomain" \
  -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" -H "Content-Type: application/json" \
  -d "{\"subdomain\":\"$2\"}" | python3 -m json.tool
