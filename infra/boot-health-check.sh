#!/usr/bin/env bash
# boot-health-check.sh — runs before listen starts on every boot or crash recovery.
# Cleans up orphaned state, then execs into uvicorn.

set -euo pipefail

REPO="/Users/dean-bot/mac-mini-agent"
JOBS_DIR="$REPO/apps/listen/jobs"
LOGS_DIR="$REPO/logs"
JOURNAL_DIR="/Users/dean-bot/agent-brain/05-journal"
DATE="$(date +%Y-%m-%d)"
TIMESTAMP="$(date +%Y-%m-%dT%H:%M:%S)"

mkdir -p "$LOGS_DIR" "$JOURNAL_DIR"

log() {
    echo "[$TIMESTAMP] $*" | tee -a "$LOGS_DIR/health-check.log"
}

log "=== boot-health-check starting ==="

# 1. Kill orphaned job-* tmux sessions
orphan_sessions=$(tmux list-sessions -F '#{session_name}' 2>/dev/null | grep '^job-' || true)
if [[ -n "$orphan_sessions" ]]; then
    log "Killing orphaned tmux sessions: $(echo "$orphan_sessions" | tr '\n' ' ')"
    echo "$orphan_sessions" | xargs -I{} tmux kill-session -t {} 2>/dev/null || true
else
    log "No orphaned tmux sessions found"
fi

# 2. Kill orphaned worker.py and claude processes
worker_pids=$(pgrep -f 'worker\.py' 2>/dev/null || true)
if [[ -n "$worker_pids" ]]; then
    log "Killing orphaned worker.py PIDs: $worker_pids"
    echo "$worker_pids" | xargs kill -9 2>/dev/null || true
fi

claude_pids=$(pgrep -f 'claude --dangerously-skip-permissions' 2>/dev/null || true)
if [[ -n "$claude_pids" ]]; then
    log "Killing orphaned claude PIDs: $claude_pids"
    echo "$claude_pids" | xargs kill -9 2>/dev/null || true
fi

# 3. Rewrite status: running → status: failed for orphaned job YAMLs
orphaned_count=0
if [[ -d "$JOBS_DIR" ]]; then
    for job_file in "$JOBS_DIR"/*.yaml; do
        [[ -e "$job_file" ]] || continue
        status=$(grep '^status:' "$job_file" | awk '{print $2}' | tr -d "'\"")
        if [[ "$status" == "running" ]]; then
            log "Marking orphaned job as failed: $(basename "$job_file")"
            yq e '.status = "failed" | .summary = "Job orphaned during agent restart — status set to failed by boot-health-check"' \
                -i "$job_file" 2>/dev/null || \
                sed -i '' "s/^status: running/status: failed/" "$job_file"
            orphaned_count=$((orphaned_count + 1))
        fi
    done
fi
log "Orphaned jobs marked failed: $orphaned_count"

# 4. Delete stale steer temp files
steer_files=$(ls /tmp/steer-sysprompt-*.txt /tmp/steer-prompt-*.txt 2>/dev/null || true)
if [[ -n "$steer_files" ]]; then
    log "Deleting stale steer temp files"
    rm -f /tmp/steer-sysprompt-*.txt /tmp/steer-prompt-*.txt
fi

# 5. Check if port 7600 is already bound — kill the process if so
port_pid=$(lsof -ti tcp:7600 2>/dev/null || true)
if [[ -n "$port_pid" ]]; then
    log "Port 7600 already bound by PID $port_pid — killing"
    kill -9 "$port_pid" 2>/dev/null || true
    sleep 1
fi

# 6. Write structured journal entry
journal_file="$JOURNAL_DIR/$DATE.md"
{
    echo ""
    echo "## $TIMESTAMP — boot-health-check"
    echo ""
    echo "- Orphaned tmux sessions killed: $(echo "$orphan_sessions" | grep -c . 2>/dev/null || echo 0)"
    echo "- Worker PIDs killed: $(echo "$worker_pids" | grep -c . 2>/dev/null || echo 0)"
    echo "- Claude PIDs killed: $(echo "$claude_pids" | grep -c . 2>/dev/null || echo 0)"
    echo "- Orphaned job YAMLs marked failed: $orphaned_count"
    echo "- Port 7600 conflict resolved: $([ -n "$port_pid" ] && echo "yes (PID $port_pid)" || echo "no")"
    echo "- Listen server starting now"
} >> "$journal_file"

log "Journal entry written to $journal_file"
log "=== boot-health-check complete — starting listen server ==="

# 7. exec into uvicorn — replaces this shell process cleanly
exec /opt/homebrew/bin/uv run python main.py
