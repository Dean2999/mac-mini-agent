# Mac Mini Agent — Claude Code Instructions

## Second Brain

The agent knowledge base is at `/Users/dean-bot/agent-brain/`.

- `index.md` — entry point and table of contents
- `01-tools/` — steer, drive, listen, direct command references
- `02-patterns/` — reusable automation patterns
- `03-runbooks/` — step-by-step procedures for common tasks
- `04-environment/` — mac-mini config and permissions
- `05-journal/` — agent observations and lessons learned

Read relevant notes before acting. Write observations to the journal after.

## Project Overview

Four CLIs for full macOS agent automation:
- **steer** — GUI control (screenshots, OCR, click, type)
- **drive** — terminal control (tmux sessions, process management)
- **listen** — HTTP job server (port 7600)
- **direct** — CLI client for listen

## Key Commands

```bash
just listen          # Start the job server
just send "prompt"   # Submit a job
just jobs            # List all jobs
just latest          # Show latest job details
```
