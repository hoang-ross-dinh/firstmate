## 1. Launch scrub

- [x] 1.1 Add the single name list and the `unset` line helper to `bin/fm-spawn.sh`
- [x] 1.2 Send the line into the pane before the first export, skipping allowlisted names
- [x] 1.3 Document the behavior in the script header and `docs/configuration.md`

## 2. Checks

- [x] 2.1 Add `tests/fm-spawn-env-scrub.test.sh` with synthetic names and values
- [x] 2.2 Run the neighboring spawn suites one at a time
