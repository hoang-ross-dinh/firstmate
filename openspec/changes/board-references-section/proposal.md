## Why

A worker report is a file path, and the first mate writes it into a task summary as a "Report: <path>" line.
The captain asked for that path to sit with the task's other links instead of inside the summary text.
The panel section that holds links is named "Tickets & MRs", which no longer fits once it also holds reports.

## What Changes

- Rename the detail-panel section from "Tickets & MRs" to "References".
- Add a `report` link kind. Its code is the file path and its url is optional, because a path has no page to open. A url that is present must still be http or https.
- Show reports as their own "Reports" group in References, as plain text when there is no url, and never as a row chip.
- Lift a stand-alone "Report: <path>" summary line into a report link at publish, so `fm-recap-item.sh` gets the same result with no change to its summary handling.
- Let `fm-recap-item.sh --add-link` take `kind=report` with no url.

Smallest design: one new link kind, handled by the existing link storage, validation, and panel groups. No new recap field.

Out of scope: any other detail-panel field or layout change.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `recap-board-links`: the report kind, its optional url, the lift from the summary, and the References section.
- `recap-item-command`: the editor accepts a report link with no url.

## Impact

`bin/fm-recap-publish.sh`, `bin/fm-recap-item.sh`, the board template, and the two recap test suites.
Existing logs stay valid, and a summary that already carries a Report line is lifted on its next publish.
