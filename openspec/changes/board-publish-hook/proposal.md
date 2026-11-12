## Why

The first mate publishes the Fleet Recap board by hand after it handles fleet events.
It can end a turn after a second mate reported a decision or an outcome without publishing, so the captain reads a stale board.
In one observed window a captain-facing outcome arrived, the first mate handled six more fleet events, and the board stayed unpublished for 93 minutes.
A written rule in the first mate's memory did not prevent this.

## What Changes

- Add `bin/fm-board-publish-guard.sh`, a Claude Stop hook for the main home.
- The hook blocks the turn end once with a short message when a second mate wrote a captain-facing event after the last board publish and the oldest such event is older than a debounce window.
- Inside the window the hook stays silent, so events that arrive close together cost one publish.
- Add `fm-board-publish-guard.sh ack`, which records that the current events need no board change.
- Add the optional local `config/board-publish-debounce` file for the window, with a default of 30 seconds, because the rule is to publish in the same turn.
- Register the hook in the tracked `.claude/settings.json` next to the turn-end guard.

Out of scope: other primary harnesses, events from the main home's own workers, and any change to the publish command or the iteration log.

## Capabilities

### New Capabilities

- `board-publish-reminder`: the debounced turn-end reminder to publish the Fleet Recap board and its acknowledgement.

### Modified Capabilities

None.

## Impact

- New hook `bin/fm-board-publish-guard.sh` and its test `tests/fm-board-publish-guard.test.sh`.
- `.claude/settings.json` gains one Stop entry, and `tests/fm-turnend-guard.test.sh` counts it among the tracked entries that stay inert under Grok.
- `docs/configuration.md` documents `config/board-publish-debounce`.
- `bin/fm-recap-publish.sh` and the iteration log format are unchanged.
