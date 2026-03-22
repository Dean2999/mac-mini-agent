---
description: Install launchd plists for auto-start, crash recovery, and daily reboot
---

# Purpose

Install the full autonomy layer on the mac-mini-agent sandbox: auto-start on boot via launchd, crash recovery with KeepAlive, daily 3 AM reboot, and boot-time orphan cleanup. Run this command **on the Mac Mini** after `/install-agent-sandbox` is complete.

## Prerequisites (Manual — must be done before running this command)

This command will verify both prerequisites and abort if either fails.

**Step 1 — Disable FileVault:**
System Settings → Privacy & Security → FileVault → Turn Off FileVault
- Decryption runs in the background (may take minutes to hours)
- Verify complete: `fdesetup status` → should return `FileVault is Off.`

**Step 2 — Enable Auto-Login:**
System Settings → Users & Groups → select dean-bot → Automatic Login → On
- Only available after FileVault is off (macOS blocks this while FileVault is enabled)
- Verify: `defaults read /Library/Preferences/com.apple.loginwindow autoLoginUser` → should return `dean-bot`

## Variables

REPO: /Users/dean-bot/mac-mini-agent
LAUNCHAGENTS_DIR: ~/Library/LaunchAgents
LISTEN_PLIST: com.dean-bot.listen.plist
REBOOT_PLIST: com.dean-bot.reboot.plist
SUDOERS_FILE: /etc/sudoers.d/dean-bot-reboot

## Instructions

- Run each step individually so you can check output before proceeding
- If any step fails, stop and report — do not continue blindly
- All commands run locally via Bash on the agent device

## Workflow

### Preflight Checks

1. Verify FileVault is off:
   ```bash
   fdesetup status
   ```
   ABORT if output does not contain `FileVault is Off.` — instruct user to disable FileVault first.

2. Verify auto-login is enabled:
   ```bash
   defaults read /Library/Preferences/com.apple.loginwindow autoLoginUser
   ```
   ABORT if output does not contain `dean-bot` — instruct user to enable auto-login in System Settings → Users & Groups.

### Phase 1: Prepare

3. Create logs directory:
   ```bash
   mkdir -p /Users/dean-bot/mac-mini-agent/logs
   ```

4. Make boot-health-check.sh executable:
   ```bash
   chmod +x /Users/dean-bot/mac-mini-agent/infra/boot-health-check.sh
   ```

### Phase 2: Install Listen LaunchAgent

5. Copy listen plist to LaunchAgents:
   ```bash
   cp /Users/dean-bot/mac-mini-agent/infra/com.dean-bot.listen.plist ~/Library/LaunchAgents/
   ```

6. Load the listen LaunchAgent:
   ```bash
   launchctl load -w ~/Library/LaunchAgents/com.dean-bot.listen.plist
   ```

7. Verify listen agent is loaded and running:
   ```bash
   sleep 3
   launchctl list | grep com.dean-bot.listen
   curl -sf http://localhost:7600/jobs
   ```
   PASS if launchctl shows the service and curl returns a YAML response.
   FAIL if service is missing or curl fails — check logs/listen.err.log.

### Phase 3: Install Sudoers Entry

8. Warn the user that the next step requires sudo to add a sudoers entry for passwordless reboot.
   Show the exact line that will be added:
   ```
   dean-bot ALL=(ALL) NOPASSWD: /sbin/shutdown -r now
   ```
   Ask for confirmation before proceeding.

9. Write the sudoers entry:
   ```bash
   echo 'dean-bot ALL=(ALL) NOPASSWD: /sbin/shutdown -r now' | sudo tee /etc/sudoers.d/dean-bot-reboot
   sudo chmod 440 /etc/sudoers.d/dean-bot-reboot
   ```

10. Verify sudoers syntax is valid:
    ```bash
    sudo visudo -cf /etc/sudoers.d/dean-bot-reboot
    ```
    PASS if output says `parsed OK`. FAIL if syntax error — remove the file and report the error.

### Phase 4: Install Reboot LaunchAgent

11. Copy reboot plist to LaunchAgents:
    ```bash
    cp /Users/dean-bot/mac-mini-agent/infra/com.dean-bot.reboot.plist ~/Library/LaunchAgents/
    ```

12. Load the reboot LaunchAgent:
    ```bash
    launchctl load -w ~/Library/LaunchAgents/com.dean-bot.reboot.plist
    ```

13. Verify reboot agent is loaded:
    ```bash
    launchctl list | grep com.dean-bot.reboot
    ```
    PASS if service appears in list. FAIL if missing.

### Phase 5: Test KeepAlive (Crash Recovery)

14. Stop the listen service to trigger KeepAlive restart:
    ```bash
    launchctl stop com.dean-bot.listen
    ```

15. Wait for launchd to restart it (ThrottleInterval is 10s):
    ```bash
    sleep 15
    curl -sf http://localhost:7600/jobs
    ```
    PASS if curl responds — listen recovered automatically.
    FAIL if curl fails — launchd did not restart the service.

16. Verify a journal entry was written by boot-health-check.sh:
    ```bash
    cat ~/agent-brain/05-journal/$(date +%Y-%m-%d).md | grep boot-health-check
    ```
    PASS if journal entry present. FAIL if missing.

### Phase 6: Report

Present results in this format:

## Autonomy Setup: [hostname]

### Preflight
| Check | Result |
|-------|--------|
| FileVault off | [PASS/FAIL] |
| Auto-login enabled | [PASS/FAIL] |

### Services
| Service | Loaded | Status |
|---------|--------|--------|
| com.dean-bot.listen | [yes/no] | [running PID / error] |
| com.dean-bot.reboot | [yes/no] | [scheduled 03:00 daily] |

### Tests
| Check | Result | Details |
|-------|--------|---------|
| Listen responds on port 7600 | [PASS/FAIL] | [response or error] |
| KeepAlive recovery | [PASS/FAIL] | [recovered in Xs / failed] |
| boot-health-check journal entry | [PASS/FAIL] | [entry found / missing] |
| Sudoers syntax valid | [PASS/FAIL] | [parsed OK / error] |

### Result

**[X/4 checks passed]** — [FULLY AUTONOMOUS / NEEDS ATTENTION]

If all pass: "Mac Mini will now auto-start listen on boot, recover from crashes, and reboot daily at 3 AM."
If any fail: List what needs to be fixed.
