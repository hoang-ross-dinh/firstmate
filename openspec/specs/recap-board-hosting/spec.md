# recap-board-hosting Specification

## Purpose
The Fleet Recap board is a static page that the existing Lavish session serves at a stable path.
A publish replaces only the board data, and the open page redraws in place without a reload.

## Requirements
### Requirement: Stable board path
The board build SHALL write the board page to `.lavish/bearings-board.html` under the firstmate home.
Test: `tests/fm-bearings-board.test.sh` - test_path_is_stable_and_home_scoped

#### Scenario: Same path every build
- **WHEN** the board is built twice for one home
- **THEN** both builds report the same `.lavish/bearings-board.html` path under that home

### Requirement: Sibling data file
WHEN a publish builds the board, the build SHALL write the board data to the sibling file `bearings-board.data.js`.
Test: `tests/fm-recap-publish.test.sh` - test_a_data_only_publish_leaves_the_board_page_untouched

#### Scenario: Data beside the page
- **WHEN** the first mate publishes a recap
- **THEN** `bearings-board.data.js` beside the board page holds the new board data

### Requirement: Data-only publish keeps the page
WHEN a publish changes only the board data, the build SHALL leave the board page file byte-identical.
Test: `tests/fm-recap-publish.test.sh` - test_a_data_only_publish_leaves_the_board_page_untouched

#### Scenario: Page untouched
- **WHEN** a publish runs and the board template has not changed
- **THEN** the board page file is byte-identical to its content before the publish

### Requirement: Template change rewrites the page
WHEN the board template changes, the build SHALL rewrite the board page once.
Test: `tests/fm-recap-publish.test.sh` - test_a_changed_template_rewrites_the_board_page_once

#### Scenario: New template
- **WHEN** the template differs from the page and the first mate publishes twice
- **THEN** the first publish rewrites the page and the second leaves it unchanged

### Requirement: Atomic data replace
The build SHALL replace the data file atomically, so that a reader never loads a partial file.
Test: `tests/fm-recap-publish.test.sh` - test_the_data_file_is_replaced_atomically

#### Scenario: Whole file
- **WHEN** a publish replaces the data file
- **THEN** the data file holds either the old or the new complete payload at every moment

### Requirement: Live update in place
WHEN a poll loads changed board data, the page SHALL redraw in place and keep the scroll position, the open panel, and focus.
Test: `tests/fm-recap-publish.test.sh` - test_a_poll_redraws_in_place_keeping_scroll_panel_and_focus

#### Scenario: Redraw without reload
- **WHEN** the captain has a task panel open and scrolled and a new iteration is published
- **THEN** the page shows the new data within one poll and the panel, its scroll, and focus stay

#### Scenario: Unchanged data
- **WHEN** a poll loads data identical to the data on screen
- **THEN** the page does not redraw

### Requirement: Poll interval
WHILE the board is open, the page SHALL load the board data again every 10 seconds.
Test: none

#### Scenario: Periodic load
- **WHEN** 10 seconds pass after the last load
- **THEN** the page loads the data file again

### Requirement: Redraw waits for the reader
WHILE a field has focus or holds unsent text, the page SHALL defer the redraw.
Test: `tests/fm-recap-publish.test.sh` - test_a_poll_waits_while_a_field_has_focus_or_unsent_text

#### Scenario: Typing a comment
- **WHEN** the captain is typing a comment and a poll loads new data
- **THEN** the page keeps the comment text and applies the new data after the field is released

### Requirement: Stale data note
IF a poll fails to load the board data, THEN the page SHALL keep the last data and show a stale note.
Test: `tests/fm-recap-publish.test.sh` - test_a_failed_poll_keeps_the_last_data_and_shows_a_stale_note

#### Scenario: Failed poll
- **WHEN** the data file cannot be loaded
- **THEN** the page keeps the last data and shows "Live data is stale - showing the last update"

#### Scenario: Recovery
- **WHEN** the next poll loads the data
- **THEN** the stale note disappears

### Requirement: New iteration badge
WHEN a newer iteration arrives while the reader views an older one, the page SHALL show an "Iteration N arrived" badge.
Test: `tests/fm-recap-publish.test.sh` - test_a_live_update_keeps_the_readers_place_and_badges_the_new_iteration

#### Scenario: Badge on arrival
- **WHEN** the captain views iteration 2 of 3 and iteration 4 is published
- **THEN** the page stays on iteration 2 and shows "Iteration 4 arrived"

### Requirement: Red dot on the arrived badge
The "Iteration N arrived" badge SHALL carry a red dot.
Test: `tests/fm-recap-publish.test.sh` - test_a_live_update_keeps_the_readers_place_and_badges_the_new_iteration

#### Scenario: Dot shown
- **WHEN** the arrived badge is shown
- **THEN** the badge holds one red dot

### Requirement: Arrived badge clears when viewed
WHEN the reader selects the arrived badge, the page SHALL show the newest iteration and remove the badge.
Test: `tests/fm-recap-publish.test.sh` - test_a_live_update_keeps_the_readers_place_and_badges_the_new_iteration

#### Scenario: Select badge
- **WHEN** the captain selects "Iteration 4 arrived"
- **THEN** the page shows iteration 4 of 4 and no arrived badge

### Requirement: Reader place survives a reload
WHEN the page loads with a saved view in session storage, the page SHALL restore the iteration, filter, open task, and scroll position.
Test: `tests/fm-recap-publish.test.sh` - test_a_live_update_keeps_the_readers_place_and_badges_the_new_iteration

#### Scenario: Reload keeps place
- **WHEN** the captain has iteration 2 and task A open, scrolled down, and the page reloads
- **THEN** the page shows iteration 2 with task A open at the same scroll position

### Requirement: No session storage
IF session storage is unavailable, THEN the page SHALL still render the board.
Test: `tests/fm-recap-publish.test.sh` - test_the_board_renders_without_session_storage

#### Scenario: Storage blocked
- **WHEN** the browser blocks session storage
- **THEN** the page renders the board without an error

### Requirement: Explore mode
The board page SHALL open in Lavish explore mode with annotation off.
Test: `tests/fm-recap-publish.test.sh` - test_the_built_board_opens_in_explore_mode

#### Scenario: No annotation layer
- **WHEN** the captain opens the board
- **THEN** Lavish shows the page in explore mode

### Requirement: No browser tab
WHEN a publish updates the board, the build SHALL never ask Lavish to open a browser tab.
Test: `tests/fm-recap-publish.test.sh` - test_a_publish_never_asks_lavish_to_open_a_browser_tab

#### Scenario: Quiet update
- **WHEN** the first mate publishes a recap
- **THEN** every Lavish call that the build makes for the board carries `--no-open`

### Requirement: Live session is kept
WHILE the board session is listed as open or with unread feedback, the build SHALL not reopen the session.
Test: `tests/fm-recap-publish.test.sh` - test_a_live_session_listed_with_unread_prompts_is_not_reopened

#### Scenario: Unread prompts
- **WHEN** the board session is listed with unread prompts and the first mate publishes
- **THEN** the build makes no reopen call

### Requirement: Ended session is reopened once
WHEN the build finds the board session ended, the build SHALL reopen the session once.
Test: `tests/fm-bearings-board.test.sh` - test_build_reopens_a_session_the_captain_ended

#### Scenario: Captain ended the session
- **WHEN** the captain ended the board session and the board is built
- **THEN** the build reopens the session once and the session is live

### Requirement: Session that stays ended
IF the board session is still not live after the reopen, THEN the build SHALL refuse to arm the board and exit non-zero.
Test: `tests/fm-bearings-board.test.sh` - test_build_refuses_to_arm_when_the_session_stays_ended

#### Scenario: Reopen fails
- **WHEN** the reopen leaves the session ended
- **THEN** the build arms no listener and exits non-zero

### Requirement: Bind before arm
WHEN the build arms the board, the build SHALL bind board answers to the captain-hold intake before it arms the listener.
Test: `tests/fm-bearings-board.test.sh` - test_build_injects_binds_then_arms

#### Scenario: Order of steps
- **WHEN** the board is built
- **THEN** the bind step completes before the arm step starts

### Requirement: Existing Lavish session only
The publish and build commands SHALL start no server process and open no new port.
Test: none

#### Scenario: No new listener
- **WHEN** the first mate publishes a recap
- **THEN** no new process listens on a port

#### Scenario: No wildcard bind
- **WHEN** the board scripts are searched for bind addresses
- **THEN** none binds `0.0.0.0` or `::`

### Requirement: No notification request
The board page SHALL request no browser notification, because the sandboxed Lavish frame always denies notification permission.
Test: none

#### Scenario: New iteration without a notification
- **WHEN** a new iteration arrives while the board is open
- **THEN** the page shows the arrived badge and requests no notification permission
