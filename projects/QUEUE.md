# Project Queue

The assistant works through this list top to bottom. Only one project is `active` at a time.
When a project is completed or paused, the next `queued` project is picked up automatically.

## Statuses

| Status | Meaning |
|--------|---------|
| `queued` | Waiting to be picked up |
| `active` | Currently being worked on — see `active/STATE.md` |
| `blocked` | Waiting on human input before continuing |
| `completed` | Done — archived in `completed/` |
| `on-hold` | Deliberately paused, not to be auto-picked up |

---

## Queue

<!-- Add new projects at the bottom. Reorder to reprioritize. -->
<!-- Format: | Priority | Project Name | Status | Notes | -->

| # | Project | Status | Notes |
|---|---------|--------|-------|
| 1 | _No projects yet_ | — | Add your first project below |

---

## How to add a project

Add a row to the table above with status `queued` and a brief note.
Create a file in `projects/briefs/` named `<project-name>.md` with the full brief —
what it is, what done looks like, any constraints or preferences.

Example brief file: `projects/briefs/my-feature.md`

The assistant will read the brief when it picks up the project.
