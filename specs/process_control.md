# Process Control for Drive

## Problem

Agents spawn processes via `drive run` and `drive send` but have no way to:
- See what's running (and what they started)
- Kill specific processes by PID or name
- Trace a process tree to find child processes
- Check if something is hung vs. actively working

Today agents resort to `steer` + Activity Monitor (slow, GUI-dependent) or raw `ps`/`kill` through `drive run` (fragile, requires parsing). The cleanup phase of every job suffers — orphaned processes accumulate, stale Claude Code instances sit idle, and agents can't confidently verify a kill worked.

## Decision: Extend Drive (not a new app)

Drive already owns terminal automation. Process control is tightly coupled — the processes agents need to manage were spawned through drive's tmux sessions. Adding a `proc` command group keeps the agent's toolset unified: `drive session` for tmux lifecycle, `drive proc` for process lifecycle.

## New Command Group: `drive proc`

### `drive proc list` — List processes

The agent's `ps` replacement. Fast, filtered, JSON-native.

```bash
drive proc list --json                           # All user processes
drive proc list --name claude --json             # Filter by name substring
drive proc list --session job-abc123 --json      # Processes in a tmux session
drive proc list --parent 12345 --json            # Children of a PID
```

Output:
```json
{
  "ok": true,
  "processes": [
    {
      "pid": 12345,
      "ppid": 1200,
      "name": "claude",
      "command": "claude --dangerously-skip-permissions ...",
      "cpu": 12.3,
      "memory_mb": 256,
      "elapsed": "5m32s",
      "session": "job-abc123"
    }
  ]
}
```

Key design choices:
- Default: only show current user's processes (not system noise)
- `--session` maps PIDs to tmux sessions via `tmux list-panes -F '#{pane_pid}'`
- `--name` is a case-insensitive substring match on process name or command line
- `--parent` shows direct children (one level) — use `--tree` for recursive
- Include `cpu`, `memory_mb`, `elapsed` so the agent can identify hung/idle processes

### `drive proc kill` — Kill a process

Safe, verified process termination.

```bash
drive proc kill 12345 --json                     # Kill by PID (SIGTERM)
drive proc kill --name "claude" --json           # Kill all matching name
drive proc kill 12345 --signal 9 --json          # SIGKILL (force)
drive proc kill 12345 --tree --json              # Kill PID and all children
```

Output:
```json
{
  "ok": true,
  "action": "kill",
  "killed": [12345, 12346, 12347],
  "signal": 15,
  "failed": []
}
```

Key design choices:
- Default signal: SIGTERM (15) — graceful. Agent can escalate to `--signal 9`
- `--tree` kills the entire process group/children (critical for Claude Code which spawns node subprocesses)
- `--name` requires exact count confirmation in JSON (agent sees how many matched before acting)
- Returns both `killed` and `failed` lists so the agent can verify
- Refuses to kill PID 1 or the agent's own process tree

### `drive proc tree` — Process tree visualization

Show parent-child relationships rooted at a PID or tmux session.

```bash
drive proc tree 12345 --json                     # Tree from PID
drive proc tree --session job-abc123 --json      # Tree from session's root PID
```

Output:
```json
{
  "ok": true,
  "root": 12345,
  "tree": [
    {"pid": 12345, "name": "bash", "children": [
      {"pid": 12346, "name": "claude", "children": [
        {"pid": 12347, "name": "node", "children": []}
      ]}
    ]}
  ]
}
```

Key design choices:
- `--session` resolves the tmux pane PID as the root automatically
- Recursive traversal via `ppid` relationships
- Human-readable output shows indented tree (like `pstree`)

### `drive proc top` — Resource snapshot

One-shot resource check for specific PIDs or a session. Not a live monitor — a single snapshot the agent can reason about.

```bash
drive proc top --session job-abc123 --json       # Resource use for session procs
drive proc top --pid 12345,12346 --json          # Specific PIDs
```

Output:
```json
{
  "ok": true,
  "snapshot": [
    {"pid": 12345, "name": "claude", "cpu": 45.2, "memory_mb": 512, "threads": 12, "elapsed": "12m05s", "state": "running"},
    {"pid": 12346, "name": "node", "cpu": 0.1, "memory_mb": 128, "threads": 4, "elapsed": "12m03s", "state": "sleeping"}
  ]
}
```

Key design choices:
- `state` field tells the agent if something is actively working or idle
- Single snapshot, not streaming — fits the observe-act-verify loop
- Combine with `proc list --session` to get the PIDs, then `proc top` for details

## Implementation

### Module: `apps/drive/modules/proc.py`

Core process operations using `psutil` (preferred) or fallback to `ps`/`pgrep` parsing.

```
list_processes(name=None, parent=None, session=None) -> list[ProcessInfo]
kill_process(pid, signal=15, tree=False) -> KillResult
process_tree(pid) -> TreeNode
process_snapshot(pids) -> list[ProcessSnapshot]
session_pids(session_name) -> list[int]  # tmux pane PIDs + children
```

### Command file: `apps/drive/commands/proc.py`

Click command group following the same patterns as `session.py`:
- `@click.group()` with subcommands
- `--json` flag on every subcommand
- `emit()` / `emit_error()` for output
- `DriveError` subclasses for process-specific errors

### Registration: `apps/drive/main.py`

```python
from commands.proc import proc
cli.add_command(proc)
```

### Dependencies: `apps/drive/pyproject.toml`

Add `psutil>=5.9` — cross-platform process utilities. Avoids brittle `ps` output parsing.

### Error types: `apps/drive/modules/errors.py`

```python
class ProcessNotFoundError(DriveError):
    code = "process_not_found"

class KillPermissionError(DriveError):
    code = "kill_permission_denied"
```

### Skill update: `.claude/skills/drive/SKILL.md`

Add `proc` to the command table and document the observe-kill-verify pattern:
```
1. drive proc list --session job-abc123 --json   → see what's running
2. drive proc kill 12345 --tree --json           → kill it and children
3. drive proc list --parent 12345 --json         → verify nothing survived
```

## Scope

### Phase 1 (MVP)
- `proc list` with `--name` and `--session` filters
- `proc kill` with `--tree` and `--signal`
- `psutil` integration
- Skill doc update

### Phase 2
- `proc tree` visualization
- `proc top` resource snapshots
- Session-to-PID mapping via tmux pane introspection

## What This Unlocks

- **Clean job teardown**: Agent lists session processes, kills the tree, verifies nothing remains
- **Orphan detection**: `proc list --name claude` finds stale instances across all sessions
- **Hung process recovery**: `proc top` shows CPU=0 for 10 minutes → agent kills and restarts
- **No more Activity Monitor**: Agents never need `steer` for process management again
