#!/usr/bin/env bash
# daily-summary.sh — Post a morning status summary to Discord
#
# Runs daily at 08:00. Reads current project state and queue, then
# uses claude -p to generate a brief status update posted to Discord.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

ENV_FILE="$HOME/.gstack/env"
[ -f "$ENV_FILE" ] && source "$ENV_FILE"

STATE_FILE="projects/active/STATE.md"
QUEUE_FILE="projects/QUEUE.md"

# Build context
CONTEXT="Generate a brief daily status summary for the project queue. Be concise — 3-5 lines max.
Include: what's currently active and what task it's on, how many projects are queued, any blocked items.
Post it to Discord using: curl -s -X POST \"\$DISCORD_WEBHOOK_URL\" -H 'Content-Type: application/json' -d '{\"content\": \"<your summary here>\"}'
Start the message with '📋 Daily status —'."

if [ -f "$STATE_FILE" ]; then
  CONTEXT="${CONTEXT}

## Active project (projects/active/STATE.md)
$(cat "$STATE_FILE")"
fi

if [ -f "$QUEUE_FILE" ]; then
  CONTEXT="${CONTEXT}

## Queue (projects/QUEUE.md)
$(cat "$QUEUE_FILE")"
fi

echo "$CONTEXT" | claude -p \
  --model claude-haiku-4-5-20251001 \
  --allowedTools "Bash" \
  2>&1

echo "[$(date -Iseconds)] Daily summary done."
