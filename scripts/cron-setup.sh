#!/usr/bin/env bash
# cron-setup.sh — Register all cron jobs for the autonomous assistant
#
# Run once during deployment (called by setup script).
# Safe to re-run — existing gstack cron entries are replaced, not duplicated.
#
# Jobs registered:
#   Every 30 min  — heartbeat check
#   Daily 08:00   — morning status summary posted to Discord
#   Monday 09:00  — weekly /retro
#   Monday 09:15  — weekly /gstack-upgrade check
#   After /ship   — /document-release (triggered by webhook receiver, not cron)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="$HOME/.gstack/logs"
mkdir -p "$LOG_DIR"

echo "Setting up cron jobs for gstack autonomous assistant..."

# Build the new cron entries
CRON_BLOCK="# --- gstack autonomous assistant ---
# Heartbeat: check active project every 30 minutes
*/30 * * * * $REPO_ROOT/scripts/heartbeat.sh >> $LOG_DIR/heartbeat.log 2>&1

# Daily morning status summary (8:00 AM)
0 8 * * * $REPO_ROOT/scripts/daily-summary.sh >> $LOG_DIR/daily-summary.log 2>&1

# Weekly retro (Monday 9:00 AM)
0 9 * * 1 $REPO_ROOT/scripts/inject-task.sh '/retro' >> $LOG_DIR/scheduled-tasks.log 2>&1

# Weekly gstack update check (Monday 9:15 AM) — alerts Discord if update available, does NOT auto-upgrade
15 9 * * 1 $REPO_ROOT/scripts/gstack-update-check.sh >> $LOG_DIR/scheduled-tasks.log 2>&1
# --- end gstack ---"

# Remove any existing gstack cron block, then append the new one
CURRENT_CRON=$(crontab -l 2>/dev/null || echo "")
STRIPPED=$(echo "$CURRENT_CRON" | sed '/# --- gstack autonomous assistant ---/,/# --- end gstack ---/d')

# Write the new crontab
(echo "$STRIPPED"; echo ""; echo "$CRON_BLOCK") | crontab -

echo "Cron jobs registered. Current crontab:"
echo "---"
crontab -l
echo "---"
echo ""
echo "Logs will be written to: $LOG_DIR"
echo "To remove all gstack cron jobs: crontab -e and delete the gstack block."
