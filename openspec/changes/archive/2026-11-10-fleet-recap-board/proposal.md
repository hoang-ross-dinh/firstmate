## Why

The captain reviews fleet work today through a chat Recap and the `/bearings lavish` board.
The chat Recap exists only as agent memory, and the board changes only when someone rebuilds it, so it shows stale cards.
Neither surface keeps a per-task history, so the captain cannot see what changed since the last review.

The captain asked: "Can we build a ticket management system with live feed via Web UI to replace that static page? It helps me review and provide feedback to you more efficient."

## What Changes

- Add a Fleet Recap board that replaces both the chat Recap and the `/bearings lavish` board as the one captain review surface.
- Add one publish command. Each publication records exactly one iteration in an append-only log in the main home's gitignored `data/` directory.
- Treat each backlog task as one ticket. Store a revision of a task only when its fields differ from its last revision.
- Show tasks grouped by theme code, with iteration navigation, filters, a per-task history with field diffs and note diffs, and a display window of the last 30 iterations.
- Show every registered secondmate home. Show a Jira key as a link only.
- Let the captain send hold answers through the existing captain-hold keyed-answer intake, and send comments through `fm-inbox.sh note` with a request id. Show the first mate's replies as the comment thread.
- Offer merge and dispatch as task actions that reuse the existing `merge.<task-id>` and `dispatch.charted` routes.
- Keep the existing `bin/fm-bearings-board.sh build` path and its tests working until the new board meets its acceptance criteria.
- No new server, no new port, no `0.0.0.0` or `::` bind, and no tunnel. The board stays on the existing Lavish session.

The captain dropped Beads after the grill. All backlogs stay on the tasks-axi markdown backend, and the board still reads backlogs only through tasks-axi verbs.
No Jira ticket exists for this work. The captain decided it is personal work on the firstmate harness.

Out of scope: owner-aware answer routing to secondmate homes, Jira status sync, a separate web server, and a backup of the iteration log.

## Capabilities

### New Capabilities

- `recap-iteration-log`: the publish command, the append-only iteration log, per-task revisions, and revision content.
- `recap-board-views`: the iteration view, task detail history, display window, finished-task aging, home coverage, Jira links, and fleet-integrity warnings.
- `recap-board-actions`: hold answers, comments with replies, and the merge and dispatch task actions.
- `recap-board-hosting`: the Lavish-only hosting, live reload, drafts surviving reload, the stable board path, and reopening an ended session.

### Modified Capabilities

None. The repository has no existing OpenSpec specs.

## Impact

- New publish command in `bin/`, with tests in `tests/`.
- New board template and payload schema beside the existing board template in `.agents/skills/bearings/assets/`.
- `bin/fm-bearings-board.sh` gains a Fleet Recap payload path. Its existing payload path and tests stay unchanged.
- `bin/fm-procevent-lavish.sh` and `bin/fm-procevent.sh` gain a comment route to `fm-inbox.sh note`.
- `.agents/skills/bearings/SKILL.md` changes to describe the publish command and the one-line chat pointer.
- New private file `data/recap-iterations.jsonl` in the main home. It is gitignored and has no backup.
