## 1. Command

- [x] 1.1 Add `bin/fm-recap-item.sh` with theme and key lookup, field edits, link edits, and the atomic rewrite
- [x] 1.2 Add `--new` and `--force-replace` with the validation publish applies
- [x] 1.3 Add `--summary -`, `--summary-file`, and `--clear-reply-terms`
- [x] 1.4 Add the publish hand-off, the iteration check, and the read-back warning with a changed-list fallback
- [x] 1.5 Seed link edits from the last published links when the file has none

## 2. Tests

- [x] 2.1 Add `tests/fm-recap-item.test.sh` with a stub publish for each requirement scenario
- [x] 2.2 Add one end-to-end test against the real publish command with a stubbed board build

## 3. Investigation

- [x] 3.1 Reproduce `changed: -` with a synthetic recap and find the cause in publish revision building
