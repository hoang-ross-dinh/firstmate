## 1. Hook

- [x] 1.1 Add `bin/fm-board-publish-guard.sh` with the event scan, the debounce, the one-block-per-event-set marker, and the step-aside cases
- [x] 1.2 Add the `ack` subcommand
- [x] 1.3 Register the hook in `.claude/settings.json` and count it in the tracked-entry test
- [x] 1.4 Document `config/board-publish-debounce` in `docs/configuration.md`

## 2. Tests

- [x] 2.1 Add `tests/fm-board-publish-guard.test.sh` with a temporary home, synthetic status lines, and a fake clock for each requirement scenario

## 3. Investigation

- [x] 3.1 Show from the status logs, the branch outcome log, and the iteration log that the board stayed stale while the first mate handled later events
