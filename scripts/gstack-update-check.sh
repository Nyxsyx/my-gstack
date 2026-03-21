#!/usr/bin/env bash
# gstack-update-check.sh — Check for a new gstack version and notify Discord
#
# Does NOT upgrade. Just checks and alerts. Run /gstack-upgrade manually
# (or say "upgrade gstack" to the assistant) when you're ready to apply it.
#
# Run by cron every Monday at 9:15 AM.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$HOME/.gstack/env"
[ -f "$ENV_FILE" ] && source "$ENV_FILE"

echo "[$(date -Iseconds)] Checking for gstack updates..."

# Try global install first, then local vendored copy
UPDATE_OUTPUT=""
if [ -x "$HOME/.claude/skills/gstack/bin/gstack-update-check" ]; then
  UPDATE_OUTPUT=$("$HOME/.claude/skills/gstack/bin/gstack-update-check" --force 2>/dev/null || true)
elif [ -x "$REPO_ROOT/bin/gstack-update-check" ]; then
  UPDATE_OUTPUT=$("$REPO_ROOT/bin/gstack-update-check" --force 2>/dev/null || true)
fi

# gstack-update-check outputs "UPGRADE_AVAILABLE <old> <new>" if an update exists
if echo "$UPDATE_OUTPUT" | grep -q "^UPGRADE_AVAILABLE"; then
  OLD=$(echo "$UPDATE_OUTPUT" | awk '{print $2}')
  NEW=$(echo "$UPDATE_OUTPUT" | awk '{print $3}')

  echo "[$(date -Iseconds)] Update available: v$OLD → v$NEW"

  "$REPO_ROOT/scripts/discord-notify.sh" \
    "📦 gstack v${NEW} is available (you're on v${OLD}). To upgrade, say \"upgrade gstack\" or run \`/gstack-upgrade\` in your Claude Code session."
else
  echo "[$(date -Iseconds)] gstack is up to date."
fi
