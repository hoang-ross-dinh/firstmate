## ADDED Requirements

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
