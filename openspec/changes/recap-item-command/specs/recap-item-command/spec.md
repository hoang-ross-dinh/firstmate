## ADDED Requirements

### Requirement: Select one item by theme
WHEN the command receives a recap file and a theme, it SHALL edit the one item whose "theme" field equals that theme.
IF no item or more than one item has that theme, THEN the command SHALL exit with status 1, name the theme and every matching key in its message, and leave the file unchanged.

#### Scenario: One match
- **WHEN** exactly one item has the theme and the command receives `--summary` and `--emoji`
- **THEN** the command replaces those two fields on that item and leaves every other item unchanged
- Proven by `test_a_one_match_edit_replaces_summary_and_emoji_and_publishes_once`

#### Scenario: No match
- **WHEN** no item has the theme
- **THEN** the command exits with status 1, names the theme, and does not write or publish
- Proven by `test_no_match_exits_nonzero_names_the_theme_and_writes_nothing`

#### Scenario: Two matches
- **WHEN** two items have the theme
- **THEN** the command exits with status 1, names the theme and both keys, and does not write or publish
- Proven by `test_two_matches_exit_nonzero_name_the_theme_and_both_keys`

### Requirement: Field and link edits
WHEN the command receives `--reply-term` at least once, it SHALL replace the whole reply_terms list with the given terms.
WHEN the command receives `--add-link`, it SHALL add the link and replace any link with the same code.
WHEN the command receives `--drop-link`, it SHALL remove the link with that code.
IF a dropped code does not exist on the item, THEN the command SHALL exit with status 1 and write nothing.
Link kinds SHALL be ticket, mr, slack, or doc, and a url SHALL be http or https without spaces, the same rules the publish command applies.

#### Scenario: Reply terms replace
- **WHEN** an item has two reply terms and the command receives two other `--reply-term` values
- **THEN** the item holds only the two given terms
- Proven by `test_reply_terms_given_once_or_more_replace_the_whole_list`

#### Scenario: Add links
- **WHEN** the command adds a slack link, a doc link, and a link whose code already exists
- **THEN** the item holds each code once and the repeated code carries the new url
- Proven by `test_add_link_accepts_slack_and_doc_and_replaces_a_link_with_the_same_code`

#### Scenario: Drop links
- **WHEN** the command drops an existing code, then drops a code the item lacks
- **THEN** the first call leaves an explicit empty links list and the second exits with status 1 with the file unchanged
- Proven by `test_drop_link_removes_by_code_and_an_unknown_code_is_an_error`

#### Scenario: Links the file omits
- **WHEN** the item has no links field and the last published revision holds links
- **THEN** an add or drop starts from the published links so a publish does not lose them
- Proven by `test_link_edits_start_from_the_last_published_links_when_the_file_has_none`

### Requirement: Refuse bad input before writing
IF the command receives an unknown flag, a flag without a value, a bad link spec, or no edit flag, THEN it SHALL exit with status 2 before it writes the file or calls publish.

#### Scenario: Bad input
- **WHEN** the command receives an unknown flag, a missing value, a link with a bad kind, code, or url, a repeated link field, or no edit flag
- **THEN** it exits with status 2 and the file is unchanged
- Proven by `test_a_bad_link_spec_or_flag_exits_2_before_anything_is_written`

### Requirement: Atomic rewrite
WHEN the command writes the recap file, it SHALL write a temp file in the same directory and rename it over the file, so the file is always valid `fm-recap.v1` JSON with its original mode.

#### Scenario: Valid file, no leftovers
- **WHEN** an edit succeeds or is refused
- **THEN** the file is valid JSON, keeps its mode, and no temp file remains in its directory
- Proven by `test_the_rewrite_keeps_valid_json_the_mode_and_leaves_no_temp_file`

### Requirement: Publish hand-off
Unless `--no-publish` is given, the command SHALL run the publish command in the foreground and print its iteration, changed, waiting, and url lines.
IF publish fails or prints no "iteration: N" line, THEN the command SHALL exit with status 1.
WHEN `--no-publish` is given, the command SHALL NOT call publish.

#### Scenario: No publish
- **WHEN** the command receives `--no-publish`
- **THEN** it writes the file and never calls publish
- Proven by `test_no_publish_writes_the_file_and_never_calls_publish`

#### Scenario: Missing iteration line
- **WHEN** publish succeeds without an iteration line, or fails
- **THEN** the command exits with status 1 and shows the publish output
- Proven by `test_publish_output_without_an_iteration_line_exits_nonzero`

### Requirement: Warn when the edit is not in the changed list
IF the published changed list does not contain the edited theme, THEN the command SHALL print a warning on stderr that names the theme and the item key, and SHALL still exit with status 0.
The warning exists because publish drops an entry whose key is not a backlog task, so the board shows nothing new.

#### Scenario: Theme absent from the changed list
- **WHEN** publish reports `changed: -` after an edit of theme LW
- **THEN** the command prints a warning naming LW and the item key, and a theme that is present or only prefixes another still behaves correctly
- Proven by `test_a_theme_missing_from_the_changed_list_warns_on_stderr`
