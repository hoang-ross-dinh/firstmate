## Why

A worker pane inherits its environment from the long-lived terminal backend daemon.
That daemon was started from inside a Claude session, so it held a frozen copy of that session's environment: a primary home's `FM_HOME` and state override, bootstrap and timing values, a session id, and a messaging token.
Ship and scout workers launched from another home inherited those stale values, and a secondmate or griller could read a different session's identity.

## What Changes

- `fm-spawn.sh` types one `unset` of a fixed name list into every pane launch, before any export and before the launch command.
- The list holds the stale Firstmate names (`FM_HOME`, `FM_STATE_OVERRIDE`, `FM_SPAWN_NO_GUARD`, `FM_SESSION_START_STAGE_FILE`, the `FM_BOOTSTRAP_*` and `FM_TIMING_*` families), the frozen Claude session names, and `TRACEPARENT`.
- Every value the spawn sets for the worker is set after the unset, so the scrub never removes it.
- A name the captain lists in `config/launch-env-allowlist` stays, because that file is the explicit choice to forward it.
- The scrub handles names only and never reads, compares, or logs a value.
- A test fails when a `FM_BOOTSTRAP_*` or `FM_TIMING_*` name appears under `bin/` without joining the list.

Out of scope: the relaunch session id and `bin/fm-control.sh`, `CLAUDE_CODE_AUTO_COMPACT_WINDOW`, and the shared terminal daemon's own environment, which the captain cleans once on the machine.

## Capabilities

### New Capabilities

- `spawn-env-scrub`: the launch-time unset of stale session names in a worker pane.

### Modified Capabilities

None.

## Impact

- `bin/fm-spawn.sh`: one name list, one helper, and one pane line sent before the first export.
- `docs/configuration.md`: a short section naming the behavior.
- New `tests/fm-spawn-env-scrub.test.sh`.
