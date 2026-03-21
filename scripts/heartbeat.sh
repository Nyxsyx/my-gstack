#!/usr/bin/env bash
# heartbeat.sh — Periodic autonomous check
#
# Run by cron every 30 minutes. Reads HEARTBEAT.md + current project state,
# then runs a claude -p session with full tool access to decide what to do.
# If the response is HEARTBEAT_OK, stays silent. Otherwise posts to Discord.
#
# Usage (cron): */30 * * * * /path/to/repo/scripts/heartbeat.sh >> ~/.gstack/logs/heartbeat.log 2>&1

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# Load env
ENV_FILE="$HOME/.gstack/env"
[ -f "$ENV_FILE" ] && source "$ENV_FILE"

LOG_DIR="$HOME/.gstack/logs"
mkdir -p "$LOG_DIR"

HEARTBEAT_MD="projects/HEARTBEAT.md"
STATE_FILE="projects/active/STATE.md"
QUEUE_FILE="projects/QUEUE.md"

echo "[$(date -Iseconds)] Heartbeat starting..."

# --- Build the prompt ---
PROMPT="$(cat "$HEARTBEAT_MD")"

# Append current state files as context
PROMPT="${PROMPT}

---

# Current File State"

if [ -f "$STATE_FILE" ]; then
  PROMPT="${PROMPT}

## projects/active/STATE.md

$(cat "$STATE_FILE")"
else
  PROMPT="${PROMPT}

## projects/active/STATE.md

(no active project)"
fi

if [ -f "$QUEUE_FILE" ]; then
  PROMPT="${PROMPT}

## projects/QUEUE.md

$(cat "$QUEUE_FILE")"
fi

# --- Run heartbeat via claude -p ---
# Uses a fast model for the check. Full tool access so it can update files,
# run git, and post to Discord directly if needed.
RESPONSE=$(echo "$PROMPT" | claude -p \
  --model claude-haiku-4-5-20251001 \
  --allowedTools "Bash,Read,Write,Edit" \
  2>&1) || {
    echo "[$(date -Iseconds)] ERROR: claude -p failed. Notifying Discord."
    "$REPO_ROOT/scripts/discord-notify.sh" "⚠️ Heartbeat failed to run — claude -p error. Check ~/.gstack/logs/heartbeat.log on the server."
    exit 1
  }

# --- Check response ---
TRIMMED=$(echo "$RESPONSE" | tr -d '[:space:]')

if [[ "$TRIMMED" == "HEARTBEAT_OK"* ]] || [[ "$TRIMMED" == *"HEARTBEAT_OK" ]]; then
  echo "[$(date -Iseconds)] Heartbeat OK — no action needed."
  exit 0
fi

# Non-OK response means the agent took action or surfaced something
echo "[$(date -Iseconds)] Heartbeat action taken:"
echo "$RESPONSE"

# If the agent didn't post to Discord itself (it may have via Bash curl),
# we don't double-post — trust the agent's output.
exit 0
