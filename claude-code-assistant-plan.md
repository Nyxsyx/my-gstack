# Autonomous CEO's Assistant — Claude Code Channels + gstack on WSL2

## Context
Windows 11 home server running 24/7 with Plex and NAS backup duties. Migrating from OpenClaw in WSL2. Goal is an autonomous assistant that manages mixed projects (web/app dev, scripts, automation, data/research) across the full development lifecycle — initiating work proactively, escalating to the owner only when genuinely needed, no urgency pressure on responses.

## Vision
The assistant monitors projects, decides what needs doing, and either does it or sends a low-pressure Discord ping and continues with what it can. It should feel like a capable team running in the background, not a bot waiting for commands.

---

## Autonomous Loop — How the Assistant Works

The assistant follows the OpenClaw-derived model: it works through a project queue autonomously, escalating to the owner only when genuinely blocked, and the heartbeat keeps everything moving even across crashes or idle periods.

### Key files

| File | Purpose |
|------|---------|
| `projects/QUEUE.md` | Ordered list of all projects and their status |
| `projects/HEARTBEAT.md` | Instructions the agent follows on every heartbeat tick |
| `projects/active/STATE.md` | Live state of the current project (task, status, decisions, escalations) |
| `projects/completed/` | Archived STATE.md files for finished projects |
| `projects/briefs/{name}.md` | Full brief for each project — what it is, what done looks like |

### The loop

1. **Owner adds a project** — adds a row to `QUEUE.md` with status `queued` and creates a brief in `projects/briefs/`
2. **Heartbeat fires** (every 30 min via cron) — agent reads `HEARTBEAT.md` and checks `active/STATE.md`
3. **If active project is in progress** — checks for stall (no activity >2h), resumes if stalled, otherwise replies `HEARTBEAT_OK`
4. **If active project is blocked** — checks if block is resolved, re-escalates to Discord after 24h if not
5. **If active project is completed** — archives STATE.md, picks up next `queued` project automatically
6. **If no active project** — pulls first `queued` row from `QUEUE.md`, reads its brief, creates STATE.md, begins work, posts start message to Discord

### Escalation

The agent escalates (Discord ping + sets `status: blocked`) for:
- Permission/access decisions it isn't confident about
- Two reasonable paths with meaningfully different outcomes
- Anything touching NAS, Plex, or system-level files
- Three consecutive failures on the same problem
- Missing credentials

Format: low-pressure, informational, posted once. Not repeated until 24h has passed.

### Project statuses

`queued` → `active` → `completed` (normal path)
`active` → `blocked` → `active` (after human resolves the block)
`active` → `on-hold` (manual — owner explicitly parks a project)

---

## Phase 1: Core Setup

### Step 1: Verify prerequisites in WSL2
- Check Claude Code version is 2.1.80 or higher (`claude --version`)
- Install Bun if not already present (`curl -fsSL https://bun.sh/install | bash`)
- Confirm claude.ai login works (API key auth is not supported for Channels)
- Note available RAM and CPU cores for resource planning alongside Plex

### Step 2: Install gstack
- Run `./deploy.sh` from this repo — it handles everything below automatically
- Manually: `git clone https://github.com/Nyxsyx/my-gstack.git ~/gstack && cd ~/gstack && ./setup`
- Verify skills are registered (`/office-hours` should be available)
- gstack section and escalation policy are injected into `~/.claude/CLAUDE.md` by `deploy.sh`
- **Auto-upgrade is disabled** — the agent checks for updates weekly and posts to Discord. Run `/gstack-upgrade` manually when ready.

### Step 3: Set up Discord channel
- Create a new Discord bot via the Discord Developer Portal
- Enable Message Content Intent under Privileged Gateway Intents
- Set OAuth2 permissions: Send Messages, Read Message History, Add Reactions
- Add bot to your Discord server
- In Claude Code:
  ```
  /plugin marketplace add anthropics/claude-plugins-official
  /plugin install discord@claude-plugins-official
  /discord:configure YOUR_BOT_TOKEN
  ```
- Test with fakechat first:
  ```
  /plugin install fakechat@claude-plugins-official
  claude --channels plugin:fakechat@claude-plugins-official
  ```
- Once confirmed working, launch with Discord:
  ```
  claude --channels plugin:discord@claude-plugins-official
  ```
- Lock to your account only:
  ```
  /discord:access policy allowlist
  ```

### Step 4: Set up persistent tmux session
- Install tmux: `sudo apt install tmux`
- Create named session: `tmux new-session -s claudecore`
- Launch Claude Code with channels inside tmux
- Complete Discord pairing
- Detach with `Ctrl+B, D`
- Add tmux session auto-start on WSL2 launch to your `.bashrc` or `.profile` so it survives reboots

### Step 5: Expose WSL2 filesystem to Windows
- Navigate to `\\wsl$\Ubuntu\home\yourusername\` in Windows Explorer
- Map as a network drive (e.g. `Z:\`)
- Verify project directories are browsable from Windows
- Install VS Code WSL extension for seamless editing across the boundary
- Ensure Claude Code working directory is NOT on the NAS backup target to avoid polluting backups with generated artifacts

---

## Phase 2: Proactive Triggering

### Step 6: GitHub webhook integration
- Webhook receiver is built (`webhook/server.ts`) — start with `bun run webhook` or `webhook/start.sh --tmux claudecore`
- HMAC-SHA256 signature verification via `GITHUB_WEBHOOK_SECRET` in `~/.gstack/env`
- Event → skill mappings (in `webhook/handlers.ts`):

  | GitHub Event | gstack Skill |
  |---|---|
  | New PR opened | `/review` |
  | Build failed | `/investigate` |
  | New issue filed | `/plan-ceo-review` |
  | PR approved + tests passing | `/ship` |
  | 3+ commits pushed to main | `/document-release` check |

- **Expose publicly via Cloudflare Tunnel** — run `scripts/cloudflare-setup.sh` once (requires browser login), then `deploy.sh` starts the tunnel automatically in tmux. Add the tunnel URL to GitHub repo Settings → Webhooks.

### Step 7: Scheduled tasks via cron
- All cron jobs registered by `scripts/cron-setup.sh` (called by `deploy.sh`):
  - Every 30 min: `scripts/heartbeat.sh` — autonomous project loop
  - Daily 08:00: `scripts/daily-summary.sh` — morning status to Discord
  - Monday 09:00: `/retro` injected into Claude Code session
  - Monday 09:15: `scripts/gstack-update-check.sh` — alerts Discord if update available, does NOT auto-upgrade

### Step 8: Heartbeat monitor
- Built in `scripts/monitor.sh` — runs in its own tmux window, started by `deploy.sh`
- Checks every 5 minutes:
  - tmux session alive? → restart + Discord alert
  - No pane activity for 15 min? → Discord warning
  - CPU or RAM above 85%? → Discord alert (Plex coexistence guard)
  - Webhook server responding? → restart if not
- Posts `"✅ Still running"` to Discord every hour

---

## Phase 3: Escalation Behaviour

### Step 9: Define escalation rules
- Escalation policy is defined in `scripts/claude-md-additions.md` and injected into `~/.claude/CLAUDE.md` by `deploy.sh`
- Also encoded in `projects/HEARTBEAT.md` for the autonomous heartbeat loop
- Rules and format: see the **Autonomous Loop** section above

### Step 10: Session memory between restarts
- Implemented via `projects/active/STATE.md` (replaces `CURRENT_STATE.md`)
- On session start, the agent reads `projects/active/STATE.md` and resumes in-progress or blocked work
- Session memory instructions are in `~/.claude/CLAUDE.md` (injected by `deploy.sh`)
- The heartbeat handles restart recovery automatically — manual session start self-initiates without waiting

---

## Phase 4: Smoke Testing

### Step 11: End to end test
- Trigger a GitHub webhook manually and verify it reaches Claude Code and kicks off the right skill
- Confirm Discord receives task start and completion messages
- Trigger a scheduled retro manually and verify it posts to Discord
- Kill the tmux session manually and verify the heartbeat restarts it and notifies Discord
- Simulate a resource pressure event and verify the alert fires
- Check Windows Task Manager during a busy run to confirm Plex and NAS are not impacted
- Verify `\\wsl$\` mapped drive reflects changes made by the assistant in real time

---

## Known Limitations and Future Considerations
- Channels is still a research preview — build defensively, expect occasional instability
- `/qa` browser automation requires Xvfb — handled by `scripts/xvfb-setup.sh`, called automatically by `deploy.sh`
- GitHub webhook receiver is exposed via Cloudflare Tunnel (free) — run `scripts/cloudflare-setup.sh` once before `deploy.sh`
- Slack, WhatsApp, and iMessage channel plugins are not yet available — Discord covers this for now
- Conductor (parallel sprints) can be layered on later once the single-session setup is stable
- gstack updates are manual — the agent checks weekly and alerts Discord. Run `/gstack-upgrade` at your convenience.

## Deployment Order

On the WSL2 machine, run in this order:

```bash
# 1. Clone the repo
git clone https://github.com/Nyxsyx/my-gstack.git ~/gstack
cd ~/gstack

# 2. Set up Cloudflare Tunnel (one-time, requires browser login)
./scripts/cloudflare-setup.sh

# 3. Deploy everything else
./deploy.sh
```

Then add the Cloudflare Tunnel URL to GitHub repo Settings → Webhooks.
