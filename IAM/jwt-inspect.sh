#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./jwt-inspect.sh                          # demande un token grafana (password grant)
#   ./jwt-inspect.sh id_token                 # id_token uniquement
#   ./jwt-inspect.sh access_token             # access_token uniquement
#   echo "$JWT" | ./jwt-inspect.sh decode     # décoder un JWT déjà en main

KC_URL="${KC_URL:-https://keycloak.local:31128}"
REALM="${REALM:-assurance}"
CLIENT_ID="${CLIENT_ID:-grafana}"
CLIENT_SECRET="${CLIENT_SECRET:-y01GLXxNoPLAiuUyXejeTQJXRerr0QoJCacD1BHde3xNHDPHrmoXOgGOhdWriav1yNGX7QaJl6UofGXt1jTNm2}"
USERNAME="${USERNAME:-pascal.dumont}"
PASSWORD="${PASSWORD:-Pascal.Dumont2026!}"

decode_jwt() {
  local jwt="$1"
  local part="$2"   # 1=header  2=payload
  echo "$jwt" | cut -d. -f"$part" | \
    python3 -c "
import sys, base64, json
s = sys.stdin.read().strip()
s += '=' * ((4 - len(s) % 4) % 4)
print(json.dumps(json.loads(base64.urlsafe_b64decode(s)), indent=2, ensure_ascii=False))
"
}

pretty_dates() {
  python3 -c "
import json, sys, datetime
d = json.load(sys.stdin)
for k in ('exp', 'iat', 'auth_time', 'nbf'):
    if k in d:
        d[k + '_human'] = datetime.datetime.utcfromtimestamp(d[k]).isoformat() + 'Z'
print(json.dumps(d, indent=2, ensure_ascii=False))
"
}

if [[ "${1:-}" == "decode" ]]; then
  JWT="$(cat)"
  echo "===== HEADER ====="
  decode_jwt "$JWT" 1
  echo
  echo "===== PAYLOAD ====="
  decode_jwt "$JWT" 2 | pretty_dates
  exit 0
fi

WHICH="${1:-both}"

RESP=$(curl -k -sS -X POST \
  "${KC_URL}/realms/${REALM}/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=password" \
  -d "client_id=${CLIENT_ID}" \
  -d "client_secret=${CLIENT_SECRET}" \
  -d "username=${USERNAME}" \
  -d "password=${PASSWORD}" \
  -d "scope=openid profile email groups")

if echo "$RESP" | jq -e '.error' >/dev/null 2>&1; then
  echo "Erreur Keycloak :" >&2
  echo "$RESP" | jq . >&2
  exit 1
fi

show() {
  local name="$1"
  local jwt
  jwt=$(echo "$RESP" | jq -r --arg n "$name" '.[$n] // empty')
  [[ -z "$jwt" || "$jwt" == "null" ]] && { echo "Pas de $name"; return; }
  echo "========== $name =========="
  echo
  echo "===== HEADER ====="
  decode_jwt "$jwt" 1
  echo
  echo "===== PAYLOAD ====="
  decode_jwt "$jwt" 2 | pretty_dates
  echo
}

case "$WHICH" in
  id_token)      show id_token ;;
  access_token)  show access_token ;;
  both|*)        show id_token; show access_token ;;
esac
