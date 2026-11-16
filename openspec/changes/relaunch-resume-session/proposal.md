## Why

A relaunch started a fresh Claude conversation, so a crashed or restarted worker lost its context and had only the instructions on disk plus a progress note.
The task record held no Claude session id, so nothing could point the replacement at the old conversation.

## What Changes

- `fm-spawn.sh` gives every Claude ship and scout launch its own `--session-id` and records it as `claude_session=` in the task record.
- A relaunch whose previous harness was Claude passes `--resume <id>` when the recorded id is well formed and its transcript still exists under the Claude config root the replacement uses.
- When the id is absent or the transcript is gone, the relaunch starts a fresh conversation, records its new id, and prints one `notice:` line on stderr.
- A relaunch that switches onto Claude from another harness starts fresh and prints no notice.
- Secondmates, raw launch commands, and every other harness are unchanged.
- Document the `claude_session` field and correct the statements that a relaunch never resumes a conversation.

Out of scope: the launch-time environment unset list, and any resume for a harness other than Claude.

## Capabilities

### New Capabilities

- `spawn-claude-session-resume`: record the Claude session id at launch and resume it on relaunch, with a fresh-conversation fallback.

### Modified Capabilities

- `pc-restart-skill`: the readiness checklist no longer states that a relaunch cannot resume any worker conversation.

## Impact

- `bin/fm-spawn.sh`: a session id decision before the task record is written, one launch placeholder, one record field.
- `docs/configuration.md`, `docs/agent-control.md`, the `bin/fm-control.sh` header, and `.agents/skills/pc-restart/SKILL.md`.
- `tests/fm-spawn-claude-session-resume.test.sh` is new, and `tests/fm-spawn-dispatch-profile.test.sh` expects the new launch flag.
