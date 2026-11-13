# recap-iteration-log Specification

## Purpose
The Fleet Recap publish command records each recap as one numbered iteration in a private append-only log.
Each iteration stores a revision only for the tasks that changed, so the board can show what moved between iterations.

## Requirements
### Requirement: One iteration per publish
WHEN the first mate runs `fm-recap-publish.sh publish <recap.json>`, the command SHALL append one iteration with the next sequence number.
Test: `tests/fm-recap-publish.test.sh` - test_each_publish_appends_one_iteration_with_the_next_sequence_number

#### Scenario: Next sequence number
- **WHEN** the log holds iterations 1 and 2 and the first mate publishes a recap
- **THEN** the log holds iteration 3 as its last line

### Requirement: Private log location
The command SHALL store the iteration log in `data/recap-iterations.jsonl`, which git ignores.
Test: `tests/fm-recap-publish.test.sh` - test_the_log_lives_in_gitignored_data

#### Scenario: Log is not tracked
- **WHEN** git checks whether `data/recap-iterations.jsonl` is ignored
- **THEN** git reports the path as ignored

### Requirement: Earlier lines stay unchanged
WHEN a publish appends an iteration, the command SHALL leave every earlier log line byte-identical.
Test: `tests/fm-recap-publish.test.sh` - test_earlier_log_lines_are_never_rewritten

#### Scenario: Append only
- **WHEN** the first mate publishes a third recap
- **THEN** the first two log lines are byte-identical to their content before the publish

### Requirement: Torn last line
IF the last log line is torn, THEN the command SHALL skip and report that line without rewriting it.
Test: `tests/fm-recap-publish.test.sh` - test_a_torn_last_line_is_skipped_reported_and_never_rewritten

#### Scenario: Torn line kept
- **WHEN** the log ends with a partial line and the first mate publishes
- **THEN** the command reports the torn line and the partial line is still in the log unchanged

### Requirement: No iteration without a publish
WHEN the backlog changes and no publish runs, the system SHALL create no iteration.
Test: `tests/fm-recap-publish.test.sh` - test_a_backlog_change_without_a_publish_creates_no_iteration

#### Scenario: Backlog edit alone
- **WHEN** a task changes state in the backlog and nobody runs the publish command
- **THEN** the log holds the same number of iterations as before

### Requirement: Refresh adds no iteration
WHEN the first mate runs `fm-recap-publish.sh refresh`, the command SHALL rebuild the board and append no iteration.
Test: `tests/fm-recap-publish.test.sh` - test_the_display_window_keeps_the_last_30_iterations_and_every_revision_full

#### Scenario: Refresh keeps the log length
- **WHEN** the log holds 35 iterations and the first mate runs refresh
- **THEN** the log still holds 35 iterations and the board is rebuilt

### Requirement: Revision only for changed tasks
WHEN a publish runs, the command SHALL store a revision only for each task whose stored fields differ from its last revision.
Test: `tests/fm-recap-publish.test.sh` - test_only_changed_tasks_get_a_revision; test_a_summary_change_alone_stores_a_revision

#### Scenario: Unchanged task
- **WHEN** a publish changes the state of task A and leaves task B unchanged
- **THEN** the new iteration holds a revision for A and none for B

#### Scenario: Summary change alone
- **WHEN** a publish changes only the summary of task A
- **THEN** the new iteration holds a revision for A

### Requirement: Revision content
Each revision SHALL store the task's backlog fields, hold fields, blockers, PR and issue links, note, waiting flag, and the first mate's recap fields.
Test: `tests/fm-recap-publish.test.sh` - test_a_revision_stores_every_required_field

#### Scenario: Fields present
- **WHEN** a publish stores a revision for a task
- **THEN** the revision holds the id, key, home, kind, repo, state, title, hold fields, blockers, PR URL, issue URL, note, and waiting flag
- **AND** the revision holds the summary, emoji, theme, reply terms, and close fields

### Requirement: Task key
The command SHALL key a main-home task by its bare id and a second-mate task by `<home>:<id>`.
Test: `tests/fm-recap-publish.test.sh` - test_the_real_collection_keys_a_task_by_its_bare_id_and_reads_its_quoted_title; test_second_mate_queued_in_flight_and_held_tasks_show_in_open

#### Scenario: Main and second-mate keys
- **WHEN** the main home holds task "a" and second mate "mate1" holds task "x"
- **THEN** the revisions are keyed "a" and "mate1:x"

### Requirement: Every listed task is collected
WHEN a publish runs, the command SHALL collect every task that the backlog listing returns for the main home and each readable second-mate home.
Test: `tests/fm-recap-publish.test.sh` - test_second_mate_queued_in_flight_and_held_tasks_show_in_open; test_a_backlog_task_without_a_recap_line_shows_in_open_without_a_recap_badge

#### Scenario: Second-mate tasks
- **WHEN** a second mate holds a queued task, an in-flight task, and a held task
- **THEN** the board shows all three tasks in the Open filter

#### Scenario: Task with no recap line
- **WHEN** the backlog holds a task that the recap file does not name
- **THEN** the board shows the task in the Open filter without a Recap label

### Requirement: Defaults for a task with no recap entry
WHEN the command stores a new task with no recap entry, the command SHALL give it theme misc, an empty summary, and an empty emoji.
Test: `tests/fm-recap-publish.test.sh` - test_a_backlog_task_without_a_recap_line_shows_in_open_without_a_recap_badge

#### Scenario: New task defaults
- **WHEN** a new backlog task appears and the recap does not name it
- **THEN** its revision holds theme "misc", an empty summary, and an empty emoji

### Requirement: Omitted recap fields keep their values
WHEN a recap omits a first mate field for a known task, the command SHALL keep that field's last stored value.
Test: `tests/fm-recap-publish.test.sh` - test_on_hold_is_stored_kept_cleared_and_a_bad_value_publishes_nothing

#### Scenario: Omitted field
- **WHEN** a task has on-hold text and the next recap omits the `on_hold` field
- **THEN** the task keeps its on-hold text

### Requirement: On-hold text is cleared by an empty string
WHEN a recap sets `on_hold` to an empty string, the command SHALL clear the task's stored on-hold text.
Test: `tests/fm-recap-publish.test.sh` - test_on_hold_is_stored_kept_cleared_and_a_bad_value_publishes_nothing

#### Scenario: Clear on-hold
- **WHEN** a task has on-hold text and the recap sends `"on_hold": ""`
- **THEN** the task's next revision holds no on-hold text

### Requirement: Listing limit
WHEN the backlog listing reports more tasks than it returned, the command SHALL read the listing again at the reported total.
Test: `tests/fm-recap-publish.test.sh` - test_a_listing_that_hits_the_limit_is_read_again_in_full

#### Scenario: Truncated listing
- **WHEN** the listing returns 1000 tasks and reports 1200 in total
- **THEN** the command reads the listing again and collects 1200 tasks

### Requirement: Failed task detail read
IF a task's detail read fails, THEN the command SHALL keep the task with the id, state, kind, repo, and title from the listing.
Test: `tests/fm-recap-publish.test.sh` - test_a_task_whose_show_call_fails_keeps_its_row_from_the_listing

#### Scenario: Detail read fails
- **WHEN** the listing returns task "a" and the detail read for "a" fails
- **THEN** the board still shows task "a" with its listed title and state

### Requirement: Unreadable second-mate backlog
IF a second-mate backlog is not readable, THEN the command SHALL add a warning that names the home and still publish.
Test: none

#### Scenario: Remote second mate
- **WHEN** a registered second mate has a remote or missing home
- **THEN** the board shows a warning that names the home and the publish succeeds

### Requirement: Publish during away mode
WHILE away mode is active, the publish command SHALL still build the board.
Test: `tests/fm-recap-publish.test.sh` - test_publish_builds_the_board_while_away_mode_is_active

#### Scenario: Away mode
- **WHEN** away mode is active and the first mate publishes a recap
- **THEN** the publish succeeds and the board data is updated

### Requirement: Waiting flag
WHILE a task is held for the captain with no future hold date, the command SHALL mark the task waiting.
Test: none

#### Scenario: Deferred hold
- **WHEN** a task is held for the captain until a date after today
- **THEN** its revision has waiting set to false

#### Scenario: Current hold
- **WHEN** a task is held for the captain with no hold date
- **THEN** its revision has waiting set to true

### Requirement: Invalid recap publishes nothing
IF a recap file is invalid, THEN the command SHALL write nothing and exit non-zero.
Test: `tests/fm-recap-publish.test.sh` - test_an_invalid_recap_publishes_nothing

#### Scenario: Bad recap
- **WHEN** the recap file has an invalid field
- **THEN** the log and the board data are unchanged and the command exits non-zero

### Requirement: Named validation errors
IF a recap field is invalid, THEN the command SHALL print one line per problem that names the task key and the field.
Test: `tests/fm-recap-publish.test.sh` - test_a_validation_error_names_the_task_key_and_the_field

#### Scenario: Bad link kind
- **WHEN** the second link of task "k" has an unknown kind
- **THEN** the error output holds a line that starts with `task k: links[1].kind`

### Requirement: Publish output
WHEN a publish succeeds, the command SHALL print the iteration number, the changed themes, the waiting count, and the board URL.
Test: `tests/fm-recap-publish.test.sh` - test_each_publish_appends_one_iteration_with_the_next_sequence_number (asserts the `iteration:` line only)

#### Scenario: Output lines
- **WHEN** iteration 8 publishes with changes in themes AA and ZZ and 2 tasks waiting
- **THEN** the command prints `iteration: 8`, a `changed:` line naming AA and ZZ, `waiting: 2`, and a `url:` line

### Requirement: No ticket tracker call
The publish command SHALL make no network call to a ticket tracker.
Test: none

#### Scenario: Offline ticket keys
- **WHEN** a task title names a ticket key
- **THEN** the publish completes without contacting a ticket tracker

### Requirement: Durable default recap file
The recap file SHALL default to `data/recap.json` in the firstmate home, which git ignores.
WHEN the first mate runs `fm-recap-publish.sh publish` without a path, the command SHALL publish the default file.
WHEN a path is given, the command SHALL use that path instead of the default.
IF the file to publish does not exist, THEN the command SHALL exit non-zero, name the path, name the restore command, and append no iteration.
`fm-recap-publish.sh recap-path` SHALL print the default path.

#### Scenario: Default path
- **WHEN** the first mate asks for the recap path in a home
- **THEN** the command prints `data/recap.json` under that home's data directory, and git reports it as ignored
- Proven by `test_the_recap_file_defaults_to_the_gitignored_home_data_dir`

#### Scenario: Publish without a path
- **WHEN** the default file exists and the first mate publishes without a path, then publishes with another file
- **THEN** the first iteration holds the default file's fields and the second holds the other file's fields
- Proven by `test_publish_without_a_path_reads_the_default_recap_and_an_explicit_path_wins`

#### Scenario: Missing default file
- **WHEN** no default file exists and the first mate publishes without a path
- **THEN** the command exits non-zero, the error names the default path and the restore command, and the log is not created
- Proven by `test_publish_without_a_path_and_no_default_file_names_the_path_and_restore`

### Requirement: Restore the recap from the log
WHEN the first mate runs `fm-recap-publish.sh restore`, the command SHALL write an `fm-recap.v1` recap file to the default path, or to the path it receives.
For each task in the newest readable iteration, the command SHALL take the first mate fields of that task's last stored revision: summary, emoji, theme, reply terms, close, on-hold text, and links.
The command SHALL NOT restore an answer, a backlog field, or a task that is not in the newest iteration.
The command SHALL NOT append an iteration, change the log, or build the board.
IF the log holds no readable iteration, THEN the command SHALL exit non-zero and write no file.
IF the target file is not empty and the command does not receive `--force`, THEN the command SHALL exit non-zero, name `--force`, and leave the file unchanged.
WHEN the command receives `--force`, it SHALL replace the target file through a temp file and a rename.

#### Scenario: Rebuild
- **WHEN** the log holds two iterations, task a changed in the second, and task z is absent from the second
- **THEN** the restored file holds a and b with their last first mate fields, no answer, and no z
- Proven by `test_restore_rebuilds_the_recap_from_the_last_revision_of_each_current_task`

#### Scenario: Restored file publishes with no change
- **WHEN** the first mate publishes the restored file against the same backlog
- **THEN** the iteration reports `changed: -`
- Proven by `test_a_restored_recap_publishes_with_no_change`

#### Scenario: Overwrite refusal
- **WHEN** the target file holds data, then `--force` is given, then the target is an empty file
- **THEN** the first call exits non-zero and leaves the file unchanged, `--force` replaces it, and an empty file is filled with no flag
- Proven by `test_restore_refuses_to_overwrite_a_non_empty_recap_unless_forced`

#### Scenario: Path and empty log
- **WHEN** the log is missing or empty, then holds iterations with a torn last line and the command receives a path
- **THEN** the first two calls exit non-zero and write nothing, and the last call writes only the given path
- Proven by `test_restore_takes_an_explicit_path_and_a_log_with_no_iteration_is_an_error`

#### Scenario: Log and board untouched
- **WHEN** the first mate restores the recap
- **THEN** the log is byte-identical and no board is built
- Proven by `test_restore_never_touches_the_log_or_the_board`
