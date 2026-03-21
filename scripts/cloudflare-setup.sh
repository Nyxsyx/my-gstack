#!/usr/bin/env bash
# cloudflare-setup.sh — Install cloudflared and create a named tunnel
#
# Run this ONCE manually before deploy.sh. Requires browser access to
# complete the Cloudflare login step.
#
# What it does:
#   1. Installs cloudflared
#   2. Opens browser for Cloudflare login (one-time)
#   3. Creates a named tunnel called "assistant"
#   4. Writes ~/.cloudflared/config.yml pointed at localhost:9000
#   5. Prints the tunnel URL to add to GitHub webhook settings
#
# After this runs, deploy.sh handles starting the tunnel in tmux.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$HOME/.gstack/env"
[ -f "$ENV_FILE" ] && source "$ENV_FILE" 2>/dev/null || true

TUNNEL_NAME="assistant"
WEBHOOK_PORT="${WEBHOOK_PORT:-9000}"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✓${NC} $*"; }
warn() { echo -e "${YELLOW}⚠${NC}  $*"; }
step() { echo -e "\n${GREEN}▶${NC} $*"; }

# ─── Step 1: Install cloudflared ─────────────────────────────────────────────
step "Installing cloudflared..."

if command -v cloudflared >/dev/null 2>&1; then
  ok "cloudflared already installed ($(cloudflared --version 2>&1 | head -1))"
else
  ARCH=$(dpkg --print-architecture 2>/dev/null || uname -m)
  case "$ARCH" in
    amd64|x86_64)  DEB_ARCH="amd64" ;;
    arm64|aarch64) DEB_ARCH="arm64" ;;
    *)             DEB_ARCH="amd64" ;;
  esac

  curl -fsSL "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${DEB_ARCH}.deb" \
    -o /tmp/cloudflared.deb
  sudo dpkg -i /tmp/cloudflared.deb
  rm /tmp/cloudflared.deb
  ok "cloudflared installed."
fi

# ─── Step 2: Login ────────────────────────────────────────────────────────────
step "Cloudflare login..."

if [ -f "$HOME/.cloudflared/cert.pem" ]; then
  ok "Already logged in to Cloudflare."
else
  echo ""
  echo "  A browser window will open to complete Cloudflare login."
  echo "  Log in with your Cloudflare account (free account is fine)."
  echo ""
  cloudflared tunnel login
  ok "Logged in to Cloudflare."
fi

# ─── Step 3: Create tunnel ───────────────────────────────────────────────────
step "Creating tunnel '$TUNNEL_NAME'..."

EXISTING=$(cloudflared tunnel list 2>/dev/null | grep "$TUNNEL_NAME" | awk '{print $1}' || true)

if [ -n "$EXISTING" ]; then
  TUNNEL_ID="$EXISTING"
  ok "Tunnel '$TUNNEL_NAME' already exists (ID: $TUNNEL_ID)"
else
  cloudflared tunnel create "$TUNNEL_NAME"
  TUNNEL_ID=$(cloudflared tunnel list 2>/dev/null | grep "$TUNNEL_NAME" | awk '{print $1}')
  ok "Tunnel created (ID: $TUNNEL_ID)"
fi

# ─── Step 4: Write config ────────────────────────────────────────────────────
step "Writing ~/.cloudflared/config.yml..."

mkdir -p "$HOME/.cloudflared"
CREDS_FILE=$(ls "$HOME/.cloudflared/${TUNNEL_ID}.json" 2>/dev/null || echo "$HOME/.cloudflared/${TUNNEL_ID}.json")

cat > "$HOME/.cloudflared/config.yml" <<EOF
tunnel: $TUNNEL_ID
credentials-file: $CREDS_FILE

ingress:
  - service: http://localhost:$WEBHOOK_PORT
EOF

ok "Config written to ~/.cloudflared/config.yml"

# ─── Step 5: DNS route ───────────────────────────────────────────────────────
step "Setting up DNS..."

echo ""
echo "  Choose how to expose the tunnel:"
echo "  1) Use a free *.cfargotunnel.com URL (no domain needed)"
echo "  2) Route to your own domain (e.g. hooks.yourdomain.com)"
echo ""
read -rp "  Enter choice [1/2]: " CHOICE

if [[ "$CHOICE" == "2" ]]; then
  read -rp "  Enter your hostname (e.g. hooks.yourdomain.com): " HOSTNAME
  cloudflared tunnel route dns "$TUNNEL_NAME" "$HOSTNAME"
  TUNNEL_URL="https://$HOSTNAME"
  ok "DNS route created: $TUNNEL_URL"
else
  # Quick tunnel URL — note this changes if tunnel is recreated
  TUNNEL_URL="https://${TUNNEL_ID}.cfargotunnel.com"
  warn "Using cfargotunnel.com URL. This is stable for named tunnels but less memorable."
fi

# ─── Step 6: Save tunnel URL to env ─────────────────────────────────────────
step "Saving tunnel URL..."

if grep -q "CLOUDFLARE_TUNNEL_URL" "$ENV_FILE" 2>/dev/null; then
  sed -i "s|CLOUDFLARE_TUNNEL_URL=.*|CLOUDFLARE_TUNNEL_URL=\"$TUNNEL_URL\"|" "$ENV_FILE"
else
  echo "CLOUDFLARE_TUNNEL_URL=\"$TUNNEL_URL\"" >> "$ENV_FILE"
fi

ok "Tunnel URL saved to ~/.gstack/env"

# ─── Done ────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}  Cloudflare Tunnel ready.${NC}"
echo ""
echo "  Tunnel URL: $TUNNEL_URL"
echo ""
echo "  Add this URL to GitHub → repo → Settings → Webhooks:"
echo "    Payload URL:  $TUNNEL_URL"
echo "    Content type: application/json"
echo "    Secret:       (your GITHUB_WEBHOOK_SECRET from ~/.gstack/env)"
echo "    Events:       Pull requests, Pull request reviews, Workflow runs, Issues, Pushes"
echo ""
echo "  The tunnel will be started automatically by deploy.sh."
echo "  To start it manually: cloudflared tunnel run $TUNNEL_NAME"
echo ""
