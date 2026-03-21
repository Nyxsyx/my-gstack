
## gstack

Use the /browse skill from gstack for all web browsing. Never use mcp__claude-in-chrome__* tools.

Available skills: /office-hours, /plan-ceo-review, /plan-eng-review, /plan-design-review,
/design-consultation, /review, /ship, /browse, /qa, /qa-only, /design-review,
/setup-browser-cookies, /retro, /investigate, /document-release, /codex, /careful,
/freeze, /guard, /unfreeze, /gstack-upgrade.

If gstack skills aren't working, run `cd ~/.claude/skills/gstack && ./setup` to rebuild.

## Autonomous Assistant — Session Startup

On every session start, read `projects/active/STATE.md` if it exists.
If status is `in_progress`, resume the current task immediately.
If status is `blocked`, check if the block has been resolved and resume or re-escalate.
If no active project, read `projects/QUEUE.md` and pick up the first `queued` project.

The heartbeat (run by cron every 30 min) handles this automatically, but on manual session
start you should self-initiate without waiting for the heartbeat.

## Escalation Policy

Escalate to Discord and pause work (set `status: blocked` in `projects/active/STATE.md`) when:

- A permission or access decision you are not confident about
- A choice between two reasonable paths with meaningfully different outcomes
- Anything that touches the NAS, Plex config, or system-level files outside the project scope
- Three consecutive failed attempts at the same problem
- Missing credentials or secrets required to continue

**Escalation message format:**
```
🤔 [Project: {name}] — decision point: {brief description}.
Continuing with: {safe fallback, or "nothing — waiting for input"}.
No urgency — let me know when you get a chance.
```

Post once. Do not repeat until 24 hours have passed without a response.
Do not block all work — continue with anything that does not require the blocked decision.

**What does NOT require escalation:**
- Reversible code changes (you can commit and revert)
- Choosing between equivalent implementations
- Running tests, linting, formatting
- Reading files, searching the codebase, writing documentation
- Standard git operations (commit, branch, push to non-main branches)
