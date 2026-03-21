#!/usr/bin/env bash
# monitor.sh — Session health monitor
#
# Runs continuously alongside the Claude Code session. Checks every 5 minutes:
#   1. Is the claudecore tmux session alive? Restart if not.
#   2. Has there been no activity for 15+ minutes? Post a warning to Discord.
#   3. Is RAM or CPU above threshold? Post a resource pressure alert.
#   4. Is the webhook server running? Restart if not.
#
# Posts "✅ Still running" to Discord every hour as a passive heartbeat.
#
# Usage:
#   ./scripts/monitor.sh &          # start in background
#   ./scripts/monitor.sh --tmux     # start in a tmux window called "monitor"

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="$HOME/.gstack/logs"
mkdir -p "$LOG_DIR"

ENV_FILE="$HOME/.gstack/env"
[ -f "$ENV_FILE" ] && source "$ENV_FILE"

if [[ "${1:-}" == "--tmux" ]]; then
  TMUX_SESSION="${2:-claudecore}"
  tmux new-window -t "$TMUX_SESSION" -n "monitor" \
    "cd $REPO_ROOT && $REPO_ROOT/scripts/monitor.sh 2>&1 | tee -a $LOG_DIR/monitor.log"
  echo "Monitor started in tmux window 'monitor' (session: $TMUX_SESSION)."
  exit 0
fi

# --- Config ---
TMUX_SESSION="claudecore"
CHECK_INTERVAL=300        # seconds between checks (5 min)
ACTIVITY_TIMEOUT=900      # seconds of no pane activity before warning (15 min)
CPU_THRESHOLD=85          # percent
RAM_THRESHOLD=85          # percent
HOURLY_PING_INTERVAL=3600 # seconds between "still running" pings

LAST_HOURLY_PING=0
LAST_ACTIVITY_WARN=0

notify() {
  "$REPO_ROOT/scripts/discord-notify.sh" "$1" 2>/dev/null || true
}

log() {
  echo "[$(date -Iseconds)] $1"
}

restart_claude_session() {
  log "Restarting claudecore tmux session..."
  tmux new-session -d -s "$TMUX_SESSION" \
    "cd $REPO_ROOT && source $ENV_FILE 2>/dev/null || true && claude --channels plugin:discord@claude-plugins-official"
  log "Session restarted."

  # Drain any pending tasks
  "$REPO_ROOT/scripts/inject-task.sh" --session "$TMUX_SESSION" \
    "Session was restarted by the monitor. Read projects/active/STATE.md and resume where you left off." \
    2>/dev/null || true
}

restart_webhook_server() {
  log "Restarting webhook server..."
  "$REPO_ROOT/webhook/start.sh" --tmux "$TMUX_SESSION" 2>/dev/null || true
}

log "Monitor starting. Checking every ${CHECK_INTERVAL}s."

while true; do
  NOW=$(date +%s)

  # --- 1. Check tmux session ---
  if ! tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
    log "⚠️  Session '$TMUX_SESSION' not found — restarting."
    notify "⚠️ Claude Code session crashed — restarting now."
    restart_claude_session
    sleep 10 # Give it time to start before next checks
  fi

  # --- 2. Check for inactivity (pane content hasn't changed) ---
  ACTIVITY_FILE="$HOME/.gstack/last-activity"
  PANE_CONTENT=$(tmux capture-pane -t "$TMUX_SESSION" -p 2>/dev/null | md5sum | cut -d' ' -f1)
  STORED_CONTENT=$(cat "$ACTIVITY_FILE" 2>/dev/null || echo "")

  if [ "$PANE_CONTENT" != "$STORED_CONTENT" ]; then
    echo "$PANE_CONTENT" > "$ACTIVITY_FILE"
    echo "$NOW" > "$HOME/.gstack/last-activity-time"
  else
    LAST_CHANGE=$(cat "$HOME/.gstack/last-activity-time" 2>/dev/null || echo "$NOW")
    IDLE_SECONDS=$((NOW - LAST_CHANGE))

    if [ "$IDLE_SECONDS" -gt "$ACTIVITY_TIMEOUT" ] && \
       [ "$((NOW - LAST_ACTIVITY_WARN))" -gt "$ACTIVITY_TIMEOUT" ]; then
      log "⏳ No pane activity for ${IDLE_SECONDS}s."
      notify "⏳ No activity detected for $((IDLE_SECONDS / 60)) minutes — session may be stuck."
      LAST_ACTIVITY_WARN=$NOW
    fi
  fi

  # --- 3. Resource pressure ---
  CPU=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1 | cut -d',' -f1 | xargs printf "%.0f")
  RAM=$(free | awk '/Mem:/ {printf "%.0f", $3/$2 * 100}')

  if [ "${CPU:-0}" -gt "$CPU_THRESHOLD" ]; then
    log "⚠️  CPU at ${CPU}%"
    notify "⚠️ Resource pressure: CPU at ${CPU}%. Plex or another process may be competing."
  fi

  if [ "${RAM:-0}" -gt "$RAM_THRESHOLD" ]; then
    log "⚠️  RAM at ${RAM}%"
    notify "⚠️ Resource pressure: RAM at ${RAM}%. Consider pausing heavy tasks."
  fi

  # --- 4. Check webhook server ---
  if ! curl -sf "http://localhost:${WEBHOOK_PORT:-9000}/health" > /dev/null 2>&1; then
    log "⚠️  Webhook server not responding — restarting."
    notify "⚠️ Webhook receiver was down — restarting."
    restart_webhook_server
  fi

  # --- 5. Hourly "still running" ping ---
  if [ "$((NOW - LAST_HOURLY_PING))" -gt "$HOURLY_PING_INTERVAL" ]; then
    notify "✅ Still running — $(date '+%H:%M'). CPU: ${CPU:-?}% | RAM: ${RAM:-?}%"
    LAST_HOURLY_PING=$NOW
  fi

  sleep "$CHECK_INTERVAL"
done
