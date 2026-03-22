# Remote Agent Communications Guide

> Read this document before attempting to communicate with this Mac Mini agent.
> It covers everything a remote Claude Code agent needs: connection setup, job submission, polling, and the second brain.

> **IMPORTANT — Second Brain Location:**
> The second brain lives on the Mac Mini at `dean-bot@Dean-Bots-Mac-mini.local:~/agent-brain/`.
> Do NOT create a local `~/agent-brain/` on the remote machine. Access it exclusively via SSH.

---

## This Machine

| | |
|---|---|
| **Hostname** | `Dean-Bots-Mac-mini.local` |
| **IP** | `192.168.1.247` (LAN — may change, verify with `ping Dean-Bots-Mac-mini.local`) |
| **Listen server** | `http://192.168.1.247:7600` |
| **SSH** | `ssh dean-bot@Dean-Bots-Mac-mini.local` |
| **Second brain** | `~/agent-brain/` on this machine |

---

## Architecture

```
[Remote Agent Machine]                    [This Mac Mini]
                                          listen (port 7600)
  just send "prompt"                           │
  └── direct CLI ── POST /job ───────────────▶ │
                  ◀── { job_id } ─────────────┤
                                               ├── spawns worker.py
                                               └── worker runs: claude --dangerously-skip-permissions -p "prompt"
                                                     └── agent has steer + drive access (GUI + terminal)

  just job <id> ─── GET /job/<id> ──────────▶ │
                  ◀── YAML (status, updates, summary) ──┤
```

**Security model:** Network isolation — listen server accepts connections from any host on the LAN. No authentication required within the local network.

---

## Step 1: Set Up Your Remote Machine

Run the devbox installer from your machine's copy of the mac-mini-agent repo:

```bash
/install-engineer-devbox Dean-Bots-Mac-mini.local
```

This installs `uv`, `just`, configures `AGENT_SANDBOX_URL`, and runs a 6-check verification suite. It confirms network connectivity, the listen server, SSH access, and an end-to-end job test.

If the repo isn't cloned on the remote machine yet:
```bash
git clone https://github.com/Dean2999/mac-mini-agent.git ~/mac-mini-agent
cd ~/mac-mini-agent
```

---

## Step 2: Configure the Sandbox URL

Set the target URL so all `just` commands point at this Mac Mini:

```bash
# In your shell profile or .env:
export AGENT_SANDBOX_URL=http://192.168.1.247:7600

# Or use the hostname (more reliable on LAN):
export AGENT_SANDBOX_URL=http://Dean-Bots-Mac-mini.local:7600
```

Verify it's reachable:
```bash
curl -s $AGENT_SANDBOX_URL/jobs
```
A YAML response confirms the listen server is running.

---

## Step 3: Submit and Monitor Jobs

### Submit a job

```bash
just send "your prompt here"
# Returns a job ID like: a1b2c3d4
```

### Check job status

```bash
just job <id>              # Get current YAML state
just latest                # Full details of the most recent job
just jobs                  # List all jobs
```

### Job lifecycle

```yaml
status: running     # Job accepted, agent working
status: completed   # Agent finished successfully
status: failed      # Agent exited with error
status: stopped     # Manually stopped via just stop <id>
```

### Poll until complete (manual)

```bash
# Check every 10 seconds until status != running
while true; do
  status=$(just job <id> 2>/dev/null | grep '^status:' | awk '{print $2}')
  echo "Status: $status"
  [[ "$status" != "running" ]] && break
  sleep 10
done
just job <id>
```

### Stop a job

```bash
just stop <id>
```

---

## Step 4: Read the Second Brain

The second brain is a markdown knowledge base on this Mac Mini at `~/agent-brain/`. It contains tool references, reusable patterns, runbooks, environment config, and daily journals. **Read it before starting any non-trivial task** — it prevents repeating mistakes and builds on prior work.

### Read the index

```bash
ssh dean-bot@Dean-Bots-Mac-mini.local 'cat ~/agent-brain/index.md'
```

### Read key sections

```bash
# Tool references
ssh dean-bot@Dean-Bots-Mac-mini.local 'cat ~/agent-brain/01-tools/steer.md'
ssh dean-bot@Dean-Bots-Mac-mini.local 'cat ~/agent-brain/01-tools/drive.md'

# Patterns
ssh dean-bot@Dean-Bots-Mac-mini.local 'cat ~/agent-brain/02-patterns/sentinel-pattern.md'
ssh dean-bot@Dean-Bots-Mac-mini.local 'cat ~/agent-brain/02-patterns/agent-on-agent.md'

# Runbooks
ssh dean-bot@Dean-Bots-Mac-mini.local 'cat ~/agent-brain/03-runbooks/deploy-job.md'
ssh dean-bot@Dean-Bots-Mac-mini.local 'cat ~/agent-brain/03-runbooks/debug-session.md'

# Today's journal
ssh dean-bot@Dean-Bots-Mac-mini.local "cat ~/agent-brain/05-journal/$(date +%Y-%m-%d).md"
```

### Write a journal entry after completing a task

After a task completes, append an observation to the journal so future agents benefit:

```bash
ssh dean-bot@Dean-Bots-Mac-mini.local "cat >> ~/agent-brain/05-journal/$(date +%Y-%m-%d).md" << 'EOF'

## <TIMESTAMP> — <Task name> (from remote agent)

- What was done: <one sentence>
- Outcome: <completed/failed and why>
- Key observation: <anything useful for future agents>
EOF
```

---

## Install the Send-to-Mac-Mini Skill

Copy the skill below to `.claude/commands/send-to-mac-mini.md` on the remote machine. This gives the remote Claude Code agent a `/send-to-mac-mini` slash command.

```bash
cat > ~/.claude/commands/send-to-mac-mini.md << 'SKILLEOF'
---
description: Submit a job to the mac-mini-agent listen server and monitor until complete
argument-hint: <prompt to send>
---

# Purpose

Submit a prompt to the mac-mini-agent listen server at Dean-Bots-Mac-mini.local, monitor the job until completion, and return the summary.

## Variables

SANDBOX_URL: http://Dean-Bots-Mac-mini.local:7600
MAC_MINI_SSH: dean-bot@Dean-Bots-Mac-mini.local

## Instructions

- Run each step sequentially — do not skip steps
- Use the Bash tool for all commands
- If any step fails, stop and report the error

## Workflow

### Step 1: Verify server is reachable

```bash
curl -sf http://Dean-Bots-Mac-mini.local:7600/jobs > /dev/null && echo "OK" || echo "FAIL"
```
If FAIL: report "Mac Mini listen server not reachable — check that it is powered on and connected to the LAN."

### Step 2: Read the second brain index (orient before acting)

```bash
ssh dean-bot@Dean-Bots-Mac-mini.local 'cat ~/agent-brain/index.md'
```

### Step 3: Submit the job

```bash
cd ~/mac-mini-agent/apps/direct && uv run python main.py start http://Dean-Bots-Mac-mini.local:7600 "$ARGUMENTS"
```
Save the returned job ID.

### Step 4: Poll until complete

Every 10 seconds, run:
```bash
cd ~/mac-mini-agent/apps/direct && uv run python main.py get http://Dean-Bots-Mac-mini.local:7600 <job_id>
```
Parse the `status:` field. Continue polling while `status: running`. Stop when status is `completed`, `failed`, or `stopped`.

### Step 5: Print result

Print the full job YAML. If `completed`, highlight the `summary:` field. If `failed`, highlight the `updates:` field to show where it went wrong.

### Step 6: Write journal entry

```bash
ssh dean-bot@Dean-Bots-Mac-mini.local "cat >> ~/agent-brain/05-journal/$(date +%Y-%m-%d).md" << EOF

## $(date +%Y-%m-%dT%H:%M:%S) — Remote job (from $(hostname))

- Prompt: $ARGUMENTS
- Job ID: <job_id>
- Outcome: <status>
- Summary: <one sentence from the summary field>
EOF
```
SKILLEOF
```

---

## Quick Reference

| Task | Command |
|------|---------|
| Submit a job | `just send "prompt"` |
| Submit and wait | `/send-to-mac-mini prompt` |
| Check a job | `just job <id>` |
| List all jobs | `just jobs` |
| Latest job details | `just latest` |
| Stop a job | `just stop <id>` |
| Read second brain | `ssh dean-bot@Dean-Bots-Mac-mini.local 'cat ~/agent-brain/index.md'` |
| Write journal entry | See Step 4 above |
| SSH into mac-mini | `ssh dean-bot@Dean-Bots-Mac-mini.local` |
| Check listen health | `curl http://Dean-Bots-Mac-mini.local:7600/jobs` |

---

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `curl` fails with connection refused | Listen server not running | SSH in and run `just listen` or check LaunchAgent |
| `curl` times out | Mac Mini unreachable | Check power, network, LAN connection |
| Job stuck in `running` | Agent crashed without updating YAML | SSH in, run `just jobs`, check logs in `~/mac-mini-agent/logs/` |
| SSH connection refused | Remote Login not enabled | System Settings → General → Sharing → Remote Login |
| Job returns `failed` | Agent error | Read `updates:` field in job YAML for the last known state |

For deeper debugging: see the runbook at `~/agent-brain/03-runbooks/debug-session.md` on the Mac Mini.
