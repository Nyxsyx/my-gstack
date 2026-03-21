#!/usr/bin/env bash
# xvfb-setup.sh — Set up a virtual display for headless browser automation in WSL2
#
# Required for gstack's /qa skill and Playwright-based browse commands.
# WSL2 has no display server by default — Xvfb provides a virtual one.
#
# Called by deploy.sh. Safe to re-run.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$HOME/.gstack/env"
LOG_DIR="$HOME/.gstack/logs"
mkdir -p "$LOG_DIR"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✓${NC} $*"; }
warn() { echo -e "${YELLOW}⚠${NC}  $*"; }
step() { echo -e "\n${GREEN}▶${NC} $*"; }

# ─── Step 1: Install Xvfb ────────────────────────────────────────────────────
step "Installing Xvfb..."

if command -v Xvfb >/dev/null 2>&1; then
  ok "Xvfb already installed."
else
  sudo apt-get update -qq
  sudo apt-get install -y xvfb
  ok "Xvfb installed."
fi

# ─── Step 2: Install Playwright system dependencies ──────────────────────────
step "Installing Playwright browser dependencies..."

# Playwright needs these on headless Linux
sudo apt-get install -y \
  libnss3 libnspr4 libatk1.0-0 libatk-bridge2.0-0 \
  libcups2 libdrm2 libxkbcommon0 libxcomposite1 \
  libxdamage1 libxfixes3 libxrandr2 libgbm1 libasound2 \
  --no-install-recommends 2>/dev/null || \
  warn "Some Playwright dependencies may be missing — run 'bunx playwright install-deps chromium' if /qa fails."

ok "Playwright dependencies installed."

# ─── Step 3: Start Xvfb and set DISPLAY ─────────────────────────────────────
step "Starting Xvfb virtual display..."

DISPLAY_NUM=99

# Kill any existing Xvfb on that display
pkill -f "Xvfb :${DISPLAY_NUM}" 2>/dev/null || true
sleep 1

# Start Xvfb in the background
Xvfb ":${DISPLAY_NUM}" -screen 0 1280x720x24 -ac +extension GLX +render -noreset \
  >> "$LOG_DIR/xvfb.log" 2>&1 &
XVFB_PID=$!

sleep 2

if kill -0 "$XVFB_PID" 2>/dev/null; then
  ok "Xvfb started on :${DISPLAY_NUM} (PID $XVFB_PID)"
else
  warn "Xvfb failed to start — check $LOG_DIR/xvfb.log"
fi

# ─── Step 4: Add DISPLAY to ~/.gstack/env ────────────────────────────────────
step "Persisting DISPLAY setting..."

if grep -q "^DISPLAY=" "$ENV_FILE" 2>/dev/null; then
  sed -i "s|^DISPLAY=.*|DISPLAY=\":${DISPLAY_NUM}\"|" "$ENV_FILE"
else
  echo "DISPLAY=\":${DISPLAY_NUM}\"" >> "$ENV_FILE"
fi

ok "DISPLAY=:${DISPLAY_NUM} saved to ~/.gstack/env"

# ─── Step 5: Add Xvfb auto-start to .bashrc ──────────────────────────────────
step "Adding Xvfb auto-start to ~/.bashrc..."

MARKER="# --- gstack xvfb ---"

if grep -q "$MARKER" "$HOME/.bashrc" 2>/dev/null; then
  ok "Xvfb auto-start already in ~/.bashrc"
else
  cat >> "$HOME/.bashrc" <<BASHRC_EOF

$MARKER
if command -v Xvfb >/dev/null 2>&1; then
  if ! pgrep -f "Xvfb :${DISPLAY_NUM}" >/dev/null 2>&1; then
    Xvfb :${DISPLAY_NUM} -screen 0 1280x720x24 -ac +extension GLX +render -noreset \\
      >> $LOG_DIR/xvfb.log 2>&1 &
  fi
  export DISPLAY=:${DISPLAY_NUM}
fi
# --- end gstack xvfb ---
BASHRC_EOF
  ok "Xvfb auto-start added to ~/.bashrc"
fi

# ─── Done ────────────────────────────────────────────────────────────────────
echo ""
ok "Virtual display ready. /qa and /browse will use DISPLAY=:${DISPLAY_NUM}"
echo ""
echo "  Test it: DISPLAY=:${DISPLAY_NUM} chromium --headless --screenshot /tmp/test.png https://example.com"
echo ""
