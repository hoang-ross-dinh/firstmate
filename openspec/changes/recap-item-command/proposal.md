## Why

The first mate updates the live Fleet Recap board by editing one item of the recap file and publishing.
Each edit needed a new hand-written script, which is slow to review and easy to get wrong.
A summary-only edit of an item also printed `changed: -` after publish, and nothing explained why.

## What Changes

- Add `bin/fm-recap-item.sh`. It finds one item of an `fm-recap.v1` file by its theme, edits its summary, emoji, reply terms, or links, rewrites the file atomically, and publishes.
- Warn on stderr when the edited theme is missing from the published iteration's changed list.
- Change detection in `bin/fm-recap-publish.sh` is unchanged. It compares every stored field, summary included, and maps each revision to its theme correctly.
- The cause of `changed: -` is that publish builds revisions only for tasks in the backlog collection, so an entry keyed by anything else is dropped silently. The warning names this cause.

Out of scope: board template changes, a change to which keys publish accepts, and the publish tests.

## Capabilities

### New Capabilities

- `recap-item-command`: the single-item edit command for the recap file and its publish hand-off.

### Modified Capabilities

None.

## Impact

- New command `bin/fm-recap-item.sh` and its test `tests/fm-recap-item.test.sh`.
- `bin/fm-recap-publish.sh` and the iteration log format are unchanged.
