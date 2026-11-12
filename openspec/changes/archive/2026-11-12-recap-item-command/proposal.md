## Why

The first mate updates the live Fleet Recap board by editing one item of the recap file and publishing.
Each edit needed a new hand-written script, which is slow to review and easy to get wrong.
A summary-only edit of an item also printed `changed: -` after publish, and nothing explained why.
Real use added more needs: one theme can map to several tasks, a summary can span lines, and a new task needs a new item.

## What Changes

- Add `bin/fm-recap-item.sh`. It selects one item of an `fm-recap.v1` file by theme or by task key, edits its theme, summary, emoji, reply terms, or links, rewrites the file atomically, and publishes in the same call.
- Add `--new <key>` to create an item, with `--force-replace` to overwrite an existing key.
- Accept a multi-line summary from stdin or a file, and clear the reply terms with one flag.
- After a publish, read the new iteration back and warn on stderr when the item has no revision, and say whether the key is not a backlog task.
- Change detection in `bin/fm-recap-publish.sh` is unchanged. It compares every stored field, summary included, and maps each revision to its theme correctly.
- The cause of `changed: -` is that publish builds revisions only for tasks in the backlog collection, so an entry keyed by anything else is dropped silently. The warning names this cause.

Out of scope: board template changes, a change to which keys publish accepts, and the publish tests.

## Capabilities

### New Capabilities

- `recap-item-command`: the single-item edit and create command for the recap file and its publish hand-off.

### Modified Capabilities

None.

## Impact

- New command `bin/fm-recap-item.sh` and its test `tests/fm-recap-item.test.sh`.
- `bin/fm-recap-publish.sh` and the iteration log format are unchanged.
