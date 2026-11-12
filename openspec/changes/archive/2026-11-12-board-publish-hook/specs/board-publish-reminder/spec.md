## ADDED Requirements

### Requirement: Captain-facing events since the last publish
The hook SHALL count a status line of a registered second mate when the line is captain-relevant, carries an `[at=<epoch>]` stamp, and is newer than the baseline.
The hook SHALL count a branch outcome row with verdict `captain` for a registered second mate when its epoch is newer than the baseline.
The baseline SHALL be the later of the last complete iteration's publish time and the last acknowledgement time.
The hook SHALL read each source only through its last 200 lines and SHALL make no network call.

#### Scenario: No captain-facing events
- **WHEN** the only lines after the publish are working, paused, and resolved lines, or lines without a stamp, or lines older than the publish
- **THEN** the hook exits 0 with no output
- Proven by `test_non_captain_and_unstamped_lines_are_ignored`

#### Scenario: Captain branch outcome
- **WHEN** the branch outcome log holds a captain row for a registered second mate after the publish
- **THEN** the hook counts it, and a routine row or a row for an unregistered task does not count
- Proven by `test_a_captain_branch_outcome_counts`

#### Scenario: Torn last publish line
- **WHEN** the last line of the iteration log has no final newline
- **THEN** the hook takes the publish time from the line before it
- Proven by `test_a_torn_last_publish_line_falls_back_to_the_previous_one`

### Requirement: Debounced block
WHEN the oldest counted event is at least the debounce window old, the hook SHALL exit with status 2 and print one stderr message.
The message SHALL name the event count, the second mate of the oldest event, its age (in seconds under two minutes, otherwise in minutes), the publish command, and the ack command.
WHILE the oldest counted event is younger than the window, the hook SHALL exit 0 with no output.

#### Scenario: Event older than the window
- **WHEN** one needs-decision line is 31 seconds old and the window is 30 seconds
- **THEN** the hook exits 2 and the message names the count, the second mate, the age, and the ack command
- Proven by `test_an_event_older_than_the_window_blocks`

#### Scenario: Event inside the window
- **WHEN** one done line is 29 seconds old and the window is 30 seconds
- **THEN** the hook exits 0 with no output
- Proven by `test_an_event_inside_the_window_passes_silently`

#### Scenario: Oldest event decides
- **WHEN** one event is 40 seconds old and a newer one is 10 seconds old
- **THEN** the hook exits 2 and counts both events
- Proven by `test_the_oldest_event_sets_the_debounce`

### Requirement: Debounce window setting
The debounce window SHALL be 30 seconds by default.
WHERE `config/board-publish-debounce` exists, the hook SHALL use the whole seconds on its first line as the window.
IF that first line is not whole seconds, THEN the hook SHALL use 30 seconds and print one stderr warning.

#### Scenario: Configured window
- **WHEN** the file holds 900 and the oldest event is 600 seconds old, and later 900 seconds old
- **THEN** the hook passes silently the first time and blocks the second time, and an invalid value falls back to 30 seconds with a warning
- Proven by `test_the_window_comes_from_config`

### Requirement: Clearing the reminder
WHEN a board publish is newer than every counted event, the hook SHALL exit 0 with no output.
WHEN the first mate runs `fm-board-publish-guard.sh ack`, the command SHALL record the current time as the acknowledgement time.
The hook SHALL block at most once for the same set of events, and a new event SHALL make a new set.

#### Scenario: Publish clears
- **WHEN** a publish follows the only event
- **THEN** the hook exits 0 with no output
- Proven by `test_a_publish_clears_the_block`

#### Scenario: Ack clears and no second block
- **WHEN** the hook blocked once, the next stop has the same events, then the first mate runs ack, then a new event arrives
- **THEN** the second stop passes silently, ack records its time, the acknowledged events pass silently, and the new event alone blocks
- Proven by `test_an_ack_clears_it_and_it_never_blocks_twice`

### Requirement: Main home only
The hook SHALL act only in a genuine primary checkout without a secondmate-home marker.
The hook SHALL exit 0 with no output in a second-mate home, in a task worktree, in a home without an iteration log or a second-mate registry, for a Cursor-delivered payload, and in a session that another live session holds the home lock for.

#### Scenario: Second-mate home and worker
- **WHEN** the same events exist in a home with a secondmate marker or in a linked task worktree
- **THEN** the hook exits 0 with no output there, and it blocks in the main home
- Proven by `test_a_second_mate_home_and_a_worker_are_ignored`

#### Scenario: Home without a board
- **WHEN** the home has no second-mate registry or no iteration log
- **THEN** the hook exits 0 with no output
- Proven by `test_a_home_without_a_board_or_registry_is_ignored`

#### Scenario: Lock-refused session
- **WHEN** another live session holds the home lock
- **THEN** the hook exits 0 with no output, and the same home without that lock blocks
- Proven by `test_a_lock_refused_session_steps_aside`

#### Scenario: Cursor duplicate payload
- **WHEN** the payload carries `cursor_version`
- **THEN** the hook exits 0 with no output
- Proven by `test_a_cursor_payload_stands_down`

### Requirement: Unreadable sources never block
IF a status log, the iteration log, the registry, or the branch outcome log cannot be read, THEN the hook SHALL exit 0 and print one stderr line that names it.

#### Scenario: Unreadable status log
- **WHEN** a second mate's status log has mode 000
- **THEN** the hook exits 0 and prints exactly one stderr line naming the log
- Proven by `test_an_unreadable_log_steps_aside_with_one_line`
