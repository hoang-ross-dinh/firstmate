## Why

At compact widths the board header wraps onto a second row and its opaque Previous button sits above the first filter chip.
The header stays fixed to the top of the window, so when the list scrolls beneath it the button paints over the first chip.
The layout check of the review surface reads that as covered text and blocks sending feedback until the page is fixed.

## What Changes

- Let the header scroll away with the page at viewport widths of 1024 px and below, so nothing fixed to the window can paint over list content there.
- Keep the fixed header at wider widths, where its controls sit on the right and clear the first chip.

Out of scope: board data, scripts, behavior, and the filter chips beyond the first one.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `recap-board-views`: the page header never covers the first filter chip at compact widths.

## Impact

The board template stylesheet and one real-layout test in `tests/fm-recap-publish.test.sh`.
The test needs a Chrome binary and skips without one.
