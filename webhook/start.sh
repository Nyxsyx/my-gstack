#!/usr/bin/env bash
# webhook/start.sh — Start the GitHub webhook receiver in a tmux pane
#
# Runs as a separate tmux window alongside the main Claude Code session.
# The server stays up independently — if it crashes, the monitor restarts it.
#
# Usage:
#   ./webhook/start.sh              # start in current shell
#   ./webhook/start.sh --tmux       # start in a new tmux window called "webhook"

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="$HOME/.gstack/logs"
mkdir -p "$LOG_DIR"

# Load env
ENV_FILE="$HOME/.gstack/env"
[ -f "$ENV_FILE" ] && source "$ENV_FILE"

# Validate required env
if [ -z "${GITHUB_WEBHOOK_SECRET:-}" ]; then
  echo "WARNING: GITHUB_WEBHOOK_SECRET not set in ~/.gstack/env — webhooks will not verify signatures."
fi

if [[ "${1:-}" == "--tmux" ]]; then
  TMUX_SESSION="${2:-claudecore}"
  # Create a new window in the existing session
  tmux new-window -t "$TMUX_SESSION" -n "webhook" \
    "cd $REPO_ROOT && source $ENV_FILE 2>/dev/null || true && bun run webhook/server.ts 2>&1 | tee -a $LOG_DIR/webhook.log"
  echo "Webhook receiver started in tmux window 'webhook' (session: $TMUX_SESSION)."
  echo "View it with: tmux select-window -t $TMUX_SESSION:webhook"
else
  cd "$REPO_ROOT"
  echo "Starting webhook receiver..."
  echo "Logs: $LOG_DIR/webhook.log"
  exec bun run webhook/server.ts 2>&1 | tee -a "$LOG_DIR/webhook.log"
fi
