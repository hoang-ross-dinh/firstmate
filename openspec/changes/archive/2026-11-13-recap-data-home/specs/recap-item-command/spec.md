## ADDED Requirements

### Requirement: Default recap file
WHEN the command's first argument holds a slash or ends in `.json`, it SHALL use that argument as the recap path.
WHEN the first argument is anything else, the command SHALL use the default recap path that `fm-recap-publish.sh recap-path` prints.
IF the default recap file does not exist, THEN the command SHALL exit with status 1, name the path and the restore command, and create no file.

#### Scenario: Default and explicit path
- **WHEN** the command receives `--key`, a theme, or a path as its first argument
- **THEN** the first two edit the default file, and the path edits only that file
- Proven by `test_no_recap_path_uses_the_default_file_that_publish_names`

#### Scenario: Missing default file
- **WHEN** the default file does not exist
- **THEN** the command exits with status 1 and the error names the path and `fm-recap-publish.sh restore`
- Proven by `test_a_missing_default_file_names_the_path_and_the_restore_command`

#### Scenario: Real publish
- **WHEN** the command creates an item with no path against the real publish command
- **THEN** the edit lands in the home's default file and the publish reports the changed theme
- Proven by `test_against_the_real_publish_the_default_file_is_the_one_publish_reads`
