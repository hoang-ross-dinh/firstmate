## 1. Launch and record

- [x] 1.1 Generate a session id for a claude ship or scout launch and pass it with `--session-id`
- [x] 1.2 Record `claude_session=` in the task record and keep it across relaunch
- [x] 1.3 On relaunch, pass `--resume` when the recorded id and its transcript exist, else start fresh with a notice

## 2. Documentation

- [x] 2.1 Document the field in `docs/configuration.md` and the relaunch behavior in `docs/agent-control.md`
- [x] 2.2 Correct the pc-restart skill and its spec

## 3. Tests

- [x] 3.1 Add `tests/fm-spawn-claude-session-resume.test.sh` with a fake pane and a synthetic Claude config root
- [x] 3.2 Update the expected claude launch in `tests/fm-spawn-dispatch-profile.test.sh`
