#!/usr/bin/env bash
# inject-task.sh — Send a task prompt into the active tmux Claude Code session
#
# Used by the webhook receiver and scheduled triggers to feed work into the
# main always-on Claude Code session (tmux session: claudecore).
#
# Usage:
#   ./scripts/inject-task.sh "Run /review on the open PR"
#   ./scripts/inject-task.sh --session mysession "Run /retro"
#
# If the session is busy (waiting for input), the prompt is queued to a
# pending file and a follow-up check reschedules it.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMUX_SESSION="claudecore"
PENDING_FILE="$HOME/.gstack/pending-tasks"

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --session|-s)
      TMUX_SESSION="$2"
      shift 2
      ;;
    *)
      break
      ;;
  esac
done

TASK="${1:-}"
if [ -z "$TASK" ]; then
  echo "Usage: inject-task.sh [--session name] <task prompt>" >&2
  exit 1
fi

# --- Check tmux session exists ---
if ! tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
  echo "ERROR: tmux session '$TMUX_SESSION' not found." >&2
  echo "Is the Claude Code session running? Start it with: tmux new-session -s $TMUX_SESSION" >&2

  # Queue for when the session comes back
  mkdir -p "$(dirname "$PENDING_FILE")"
  echo "$TASK" >> "$PENDING_FILE"
  echo "Task queued to $PENDING_FILE — will be injected when session restarts."
  exit 0
fi

# --- Inject the task ---
# Send the prompt text followed by Enter to submit it to Claude Code.
# Claude Code in --channels mode reads from stdin in the tmux pane.
tmux send-keys -t "$TMUX_SESSION" "$TASK" Enter

echo "Task injected into tmux session '$TMUX_SESSION'."

# --- Drain any queued tasks ---
# If there were pending tasks from when the session was down, inject them now.
if [ -f "$PENDING_FILE" ] && [ -s "$PENDING_FILE" ]; then
  echo "Draining pending tasks..."
  while IFS= read -r queued_task; do
    sleep 2  # Brief pause between injections so Claude can start processing
    tmux send-keys -t "$TMUX_SESSION" "$queued_task" Enter
    echo "Injected queued task: $queued_task"
  done < "$PENDING_FILE"
  rm "$PENDING_FILE"
  echo "Pending queue drained."
fi
