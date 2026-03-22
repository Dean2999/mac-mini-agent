---
description: Submit a job to the mac-mini-agent listen server and monitor until complete
---

# Purpose

Submit a prompt to the mac-mini-agent listen server and poll until the job completes. Works from any Claude Code session on any machine that can reach the sandbox.

## Usage

```
/submit-mac-mini-job <prompt>
```

The prompt is taken from `$ARGUMENTS`.

## Variables

DEFAULT_URL: http://localhost:7600
POLL_INTERVAL: 10

## Instructions

- Resolve the sandbox URL from the `AGENT_SANDBOX_URL` environment variable, falling back to `http://localhost:7600`
- Run each step via Bash, checking output before proceeding
- Poll every 10 seconds until status is no longer `running`
- Print the full job YAML when complete

## Workflow

1. Resolve the sandbox URL:
   ```bash
   SANDBOX_URL="${AGENT_SANDBOX_URL:-http://localhost:7600}"
   echo "Sandbox URL: $SANDBOX_URL"
   ```

2. Verify the listen server is reachable:
   ```bash
   curl -sf "$SANDBOX_URL/jobs"
   ```
   ABORT if curl fails — tell user to check that the listen server is running (`just listen` or verify the LaunchAgent is loaded).

3. Submit the job:
   ```bash
   cd /Users/dean-bot/mac-mini-agent/apps/direct && \
   uv run python main.py start "$SANDBOX_URL" "$ARGUMENTS"
   ```
   Capture the `job_id` from the response.

4. Poll for completion every 10 seconds:
   ```bash
   while true; do
     result=$(cd /Users/dean-bot/mac-mini-agent/apps/direct && uv run python main.py get "$SANDBOX_URL" "<job_id>")
     status=$(echo "$result" | grep '^status:' | awk '{print $2}')
     echo "[$(date +%H:%M:%S)] status: $status"
     if [[ "$status" != "running" ]]; then
       break
     fi
     sleep 10
   done
   ```

5. Print the full job YAML:
   ```bash
   cd /Users/dean-bot/mac-mini-agent/apps/direct && \
   uv run python main.py get "$SANDBOX_URL" "<job_id>"
   ```

6. Report the final status:
   - `completed` — job succeeded, show summary field
   - `failed` — job failed, show updates field for error details
   - `stopped` — job was manually stopped
