#!/usr/bin/env bash
# discord-notify.sh — Post a message to Discord via webhook
#
# Usage:
#   ./scripts/discord-notify.sh "message text"
#
# Requires: DISCORD_WEBHOOK_URL set in environment (or ~/.gstack/env)
#
# The webhook URL is set during setup. Store it in ~/.gstack/env:
#   DISCORD_WEBHOOK_URL=https://discord.com/api/webhooks/...

set -euo pipefail

# Load env if not already set
ENV_FILE="$HOME/.gstack/env"
if [ -f "$ENV_FILE" ] && [ -z "${DISCORD_WEBHOOK_URL:-}" ]; then
  # shellcheck source=/dev/null
  source "$ENV_FILE"
fi

if [ -z "${DISCORD_WEBHOOK_URL:-}" ]; then
  echo "ERROR: DISCORD_WEBHOOK_URL not set. Add it to ~/.gstack/env" >&2
  exit 1
fi

MESSAGE="${1:-}"
if [ -z "$MESSAGE" ]; then
  echo "Usage: discord-notify.sh <message>" >&2
  exit 1
fi

# Truncate to Discord's 2000 char limit
MESSAGE="${MESSAGE:0:2000}"

# Escape for JSON
ESCAPED=$(printf '%s' "$MESSAGE" | python3 -c "
import sys, json
print(json.dumps(sys.stdin.read()))
")

curl -s -X POST "$DISCORD_WEBHOOK_URL" \
  -H "Content-Type: application/json" \
  -d "{\"content\": $ESCAPED}" \
  > /dev/null

echo "Discord notification sent."
