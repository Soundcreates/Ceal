#!/usr/bin/env sh
set -eu

PORT="${1:-3000}"
ENV_FILE="${2:-.env}"

if [ ! -f "$ENV_FILE" ]; then
  echo "Missing $ENV_FILE in $(pwd)"
  exit 1
fi

IP="$(hostname -I | awk '{print $1}')"
if [ -z "$IP" ]; then
  echo "Could not detect LAN IP"
  exit 1
fi

BASE_URL="http://$IP:$PORT/v1"

if grep -q '^API_BASE_URL=' "$ENV_FILE"; then
  sed -i "s|^API_BASE_URL=.*$|API_BASE_URL=$BASE_URL|" "$ENV_FILE"
else
  printf '\nAPI_BASE_URL=%s\n' "$BASE_URL" >> "$ENV_FILE"
fi

echo "Updated $ENV_FILE"
echo "API_BASE_URL=$BASE_URL"
