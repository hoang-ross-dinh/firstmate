## ADDED Requirements

### Requirement: Existing Lavish session only
The board SHALL be served only by the existing Lavish session on its existing address.
The change SHALL open no new port and SHALL bind no `0.0.0.0` or `::` address.

#### Scenario: No new listener
- **WHEN** the publish command runs
- **THEN** it starts no server process and opens no port

#### Scenario: No wildcard bind
- **WHEN** the change's scripts are searched for bind addresses
- **THEN** none binds `0.0.0.0` or `::`

### Requirement: Live reload
WHEN a publish completes, the open board SHALL reload by itself at the same URL.
WHEN the board reloads, unsent comment text and queued answers SHALL survive the reload.

#### Scenario: Reload at same URL
- **WHEN** a publish rewrites the board file while the captain has the board open
- **THEN** the open board reloads and keeps its session URL

#### Scenario: Draft survives
- **WHEN** the captain has typed an unsent comment and a publish reloads the board
- **THEN** the comment text is still present after the reload

#### Scenario: Comment box markup
- **WHEN** the template renders a comment box
- **THEN** the box uses the Lavish question markup so Lavish keeps its text

### Requirement: Stable board path
The board SHALL replace the `/bearings lavish` board at its stable path.
Plain `/bearings` and `/bearings file` SHALL keep their current behavior.

#### Scenario: Same path
- **WHEN** the new board publishes
- **THEN** it is written to `$FM_HOME/.lavish/bearings-board.html`

#### Scenario: Other bearings modes
- **WHEN** the captain runs plain `/bearings` or `/bearings file`
- **THEN** the chat digest and the report file behave as before this change

### Requirement: Ended session reopens
IF the captain ended the Lavish session from the browser, THEN the next publish SHALL reopen it through the existing `fm-bearings-board.sh build` sequence.

#### Scenario: Reopen after browser end
- **WHEN** the captain ended the session and the first mate publishes
- **THEN** the publish reopens the session, binds the answer source, and arms the listener through the existing build sequence

### Requirement: Existing build path stays working
The existing `bin/fm-bearings-board.sh build` payload path and its tests SHALL keep working until the new board meets its acceptance criteria.

#### Scenario: Old payload
- **WHEN** `fm-bearings-board.sh build` receives an `fm-bearings-board.v1` payload
- **THEN** it builds the old board exactly as before this change
