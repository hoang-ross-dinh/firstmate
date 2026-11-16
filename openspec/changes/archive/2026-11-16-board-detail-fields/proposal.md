## Why

The captain reported that the board's task details lack the information needed to act on a task and to understand it.
Two causes show in the board data.
Most asks carry reply terms but show no answer form, because the panel offers the form only for a task that the backlog holds for the captain.
The summary is one free-text string, so the problem, the meaning of each option, and what happens after an answer are missing or drift between two authors.

## What Changes

- Add two recap fields: `problem` (what is wrong or asked, and why it matters) and `options` (a list of a reply term, what it means, and what happens next).
- Derive `reply_terms` from `options`, so the two lists cannot drift.
- Show the problem first, then the summary, then a "Your call" section with each option's meaning and next step, for every ask whether its task is held or not.
- Move the hold reason into a section that is closed by default.
- Flag four gaps on the board: an ask with no problem, an option with no meaning, an ask whose task is not held, and a held task with no call.
- Waive the short-summary flag for a task that has both a problem and options, and check the problem and the option meanings for unlinked references.
- Add `--problem`, `--option`, and `--clear-options` to `fm-recap-item.sh`, and warn after a publish when an item asks but its task is not held.

Smallest design: two stored fields, one derivation, one panel layout, four flags.

Out of scope: a list of source files, a flag for an ask on a finished task, and a maximum summary length.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `recap-board-views`: storage and validation of the two fields, the panel layout, and the closed hold reason.
- `recap-board-text-warnings`: the four new flags, the short-summary waiver, and the wider unlinked reference check.
- `recap-item-command`: the problem and option flags and the ask warning.

## Impact

`bin/fm-recap-publish.sh`, `bin/fm-recap-item.sh`, the board template, the bearings skill, and the two recap test suites.
Existing logs stay valid because a task with neither field stores neither, and an existing revision is unchanged.
