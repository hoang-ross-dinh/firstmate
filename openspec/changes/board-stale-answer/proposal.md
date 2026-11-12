## Why

The Last response section of a task panel keeps the newest answer on any revision forever.
A task whose summary moved on to another topic still showed an answer about the earlier topic, so the panel read as current for work the item had left.
The first mate had to replace that answer by hand in the recap file, because the item command could not set or remove an answer.

## What Changes

- Hide the whole Last response section once a later revision changed the summary the answer was stored with. History and the comment list still show the answer and replies.
- Add `--answer-to`, `--answer-file` and `--clear-answer` to `fm-recap-item.sh`, so the answer is set from a file and removed in one call.

Out of scope: every other board field, the References section, and the publish debounce hook.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `recap-board-answers`: the Last response section hides an answer that the summary has moved past. The Last response requirements live in this capability, not in `recap-board-views`.
- `recap-item-command`: the command sets an item answer from a file and clears it.

## Impact

The board template, `bin/fm-recap-item.sh`, and their two test files.
No change to the iteration log or the `fm-recap.v1` schema.
