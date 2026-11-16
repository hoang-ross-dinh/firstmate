# recap-item-command Specification

## Purpose
TBD - created by archiving change recap-item-command. Update Purpose after archive.
## Requirements
### Requirement: Select one item by theme or key
WHEN the command receives a recap file and a theme, it SHALL edit the one item whose "theme" field equals that theme.
WHEN the command receives `--key <task-key>`, it SHALL edit the item stored under that key, where a key is a bare task id or `<home>:<id>`.
IF no item, or more than one item, has the theme, THEN the command SHALL exit with status 1, name the theme and every matching key, and leave the file unchanged.
IF no item has the key, THEN the command SHALL exit with status 1 and name the key.
IF the command receives no selector, or a theme together with `--key`, THEN it SHALL exit with status 2.

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

#### Scenario: Key picks one of several
- **WHEN** two items share a theme and the command receives `--key side:delta`
- **THEN** only that item changes, an unknown key exits with status 1, and a theme plus `--key` or no selector exits with status 2
- Proven by `test_key_selects_one_task_when_a_theme_maps_to_several`

### Requirement: Field and link edits
WHEN the command receives `--reply-term` at least once, it SHALL replace the whole reply_terms list with the given terms.
WHEN the command receives `--clear-reply-terms`, it SHALL set reply_terms to an empty list.
IF the command receives `--clear-reply-terms` together with `--reply-term`, THEN it SHALL exit with status 2.
WHEN the command receives `--add-link`, it SHALL add the link and replace any link with the same code.
WHEN the command receives `--drop-link`, it SHALL remove the link with that code.
IF a dropped code does not exist on the item, THEN the command SHALL exit with status 1 and write nothing.
Link kinds SHALL be ticket, mr, slack, doc, or report, and a url SHALL be http or https without spaces, the same rules the publish command applies, except that a report MAY omit the url.

#### Scenario: Reply terms replace
- **WHEN** an item has two reply terms and the command receives two other `--reply-term` values
- **THEN** the item holds only the two given terms
- Proven by `test_reply_terms_given_once_or_more_replace_the_whole_list`

#### Scenario: Reply terms clear
- **WHEN** the command receives `--clear-reply-terms`, or that flag with `--reply-term`
- **THEN** the first call leaves an empty list and the second exits with status 2 with the file unchanged
- Proven by `test_clear_reply_terms_sets_an_empty_list_and_conflicts_with_reply_term`

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

#### Scenario: Add a report path
- **WHEN** the command adds a report link whose code is a file path and that has no url, then adds a report link with a non-http url
- **THEN** the first link is stored with no url and the second call exits with status 2 with the file unchanged
- Proven by `test_add_link_accepts_a_report_path_with_no_url_and_checks_a_given_url`

### Requirement: Multi-line summary
WHEN the command receives `--summary -`, it SHALL read the summary from standard input.
WHEN the command receives `--summary-file <path>`, it SHALL read the summary from that file.
IF the summary file does not exist, THEN the command SHALL exit with status 2.
Both forms SHALL keep line breaks inside the summary.

#### Scenario: Stdin and file
- **WHEN** a summary with a blank line comes from stdin, and another comes from a file
- **THEN** each stored summary keeps its line breaks, and a missing file exits with status 2
- Proven by `test_a_multi_line_summary_comes_from_stdin_or_a_file`

### Requirement: Create an item
WHEN the command receives `--new <key>` with `--theme`, it SHALL add an item under that key holding the given theme, summary, emoji, reply terms, and links.
The key SHALL be a bare task id or `<home>:<id>` of letters, digits, dots, dashes, and underscores, and the theme SHALL be 1 to 16 letters, digits, dots, dashes, or underscores.
IF the key already exists, THEN the command SHALL exit with status 1 and leave the file unchanged, unless it receives `--force-replace`, which SHALL replace the whole entry.
IF the command receives `--new` without `--theme`, a bad key or theme, `--drop-link`, or `--force-replace` without `--new`, THEN it SHALL exit with status 2.

#### Scenario: Create
- **WHEN** the command creates one item with a bare key and one with a home-prefixed key
- **THEN** each item holds exactly the given fields and other items are unchanged
- Proven by `test_new_creates_an_item_for_a_bare_id_or_a_home_prefixed_key`

#### Scenario: Refuse and replace
- **WHEN** the key exists, or the key, theme, or flags are invalid
- **THEN** the command exits with status 1 or 2 and writes nothing, and `--force-replace` replaces the whole entry
- Proven by `test_new_refuses_an_existing_key_unless_force_replace_and_checks_its_input`

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
Unless `--no-publish` is given, the command SHALL run the publish command in the foreground in the same call and print its iteration, changed, waiting, and url lines.
IF publish fails or prints no "iteration: N" line, THEN the command SHALL exit with status 1.
WHEN `--no-publish` is given, the command SHALL NOT call publish.

#### Scenario: Publish in the same call
- **WHEN** the command creates an item without `--no-publish`
- **THEN** publish runs once on the recap file and the iteration and changed lines are printed
- Proven by `test_a_new_item_publishes_in_the_same_call`

#### Scenario: No publish
- **WHEN** the command receives `--no-publish`
- **THEN** it writes the file and never calls publish
- Proven by `test_no_publish_writes_the_file_and_never_calls_publish`

#### Scenario: Missing iteration line
- **WHEN** publish succeeds without an iteration line, or fails
- **THEN** the command exits with status 1 and shows the publish output
- Proven by `test_publish_output_without_an_iteration_line_exits_nonzero`

### Requirement: Warn when the edit left no revision
WHEN publish returns, the command SHALL read the new iteration back.
IF the item's key is not a task in that iteration, THEN the command SHALL print a warning on stderr that names the key and says publish ignored it.
IF the key is a task but the iteration holds no revision for it, THEN the command SHALL print a warning that no stored field differs.
IF the iteration cannot be read back, THEN the command SHALL warn when the item's theme is missing from the changed list.
The command SHALL exit with status 0 after any of these warnings.
The warning exists because publish drops an entry whose key is not a backlog task, so the board shows nothing new.

#### Scenario: Read-back reasons
- **WHEN** the iteration lacks the key in its task list, lacks it in its revisions, or has it in both, while another item of the same theme changed
- **THEN** the command warns about the missing task, warns about the missing revision, or prints no warning
- Proven by `test_the_read_back_names_a_key_that_is_not_a_backlog_task_even_when_the_theme_changed`

#### Scenario: Fallback to the changed list
- **WHEN** the iteration cannot be read back and publish reports `changed: -` for the edited theme
- **THEN** the command warns, a theme that is present or only prefixes another behaves correctly, and the exit status is 0
- Proven by `test_a_theme_missing_from_the_changed_list_warns_on_stderr`

#### Scenario: Real publish
- **WHEN** the command runs against the real publish command with a backlog of one task
- **THEN** an item keyed by that task reports a changed theme with no warning, and an item keyed by anything else reports `changed: -` with a warning naming the key
- Proven by `test_against_the_real_publish_a_non_task_key_is_reported_and_a_task_key_is_not`

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

### Requirement: Set or clear the item answer
WHEN the command receives `--answer-to <id>` with `--answer-file <path>`, it SHALL set the item's answer to that note id and the text of the file, keeping line breaks.
WHEN the command receives `--clear-answer`, it SHALL remove the answer field from the item.
IF the note id is not 1 to 64 letters, digits, dots, dashes, or underscores, the file does not exist, the text is blank or longer than 20000 characters, one of `--answer-to` and `--answer-file` is given without the other, or `--clear-answer` comes with `--answer-file`, THEN the command SHALL exit with status 2 before it writes the file or calls publish.

#### Scenario: Set then clear
- **WHEN** the command receives a note id and a multi-line Markdown file, and later `--clear-answer`
- **THEN** the item holds the answer with its line breaks, then holds no answer field, and no other field changes
- Proven by `test_answer_file_sets_the_item_answer_and_clear_answer_removes_it`

#### Scenario: Bad answer input
- **WHEN** the command receives a half-given, blank, oversized, or conflicting answer flag set
- **THEN** it exits with status 2 and the file is unchanged
- Proven by `test_a_bad_answer_flag_set_exits_2_before_anything_is_written`

### Requirement: Problem edit
WHEN the command receives `--problem`, it SHALL set the item's problem to the given text.
WHEN the value is `-`, the command SHALL read the text from stdin and keep its line breaks.
WHEN the text is empty, the command SHALL store an empty problem so the next publish clears it.
IF the text has more than 600 characters, THEN the command SHALL exit with status 2 and write nothing.

#### Scenario: Set, read from stdin, and clear
- **WHEN** the command receives a problem text, then `-` with two lines on stdin, then an empty text
- **THEN** the item holds each value in turn, the second with its line break, and the third as an empty string
- Proven by `test_problem_sets_clears_and_reads_stdin_and_a_too_long_one_exits_2`

#### Scenario: Too long
- **WHEN** the problem text has 601 characters
- **THEN** the command exits with status 2 and the file is unchanged
- Proven by `test_problem_sets_clears_and_reads_stdin_and_a_too_long_one_exits_2`

### Requirement: Option edit
WHEN the command receives `--option` at least once, it SHALL replace the whole options list with the given options.
An option spec SHALL have the form `term=..,means=..[,next=..]`, and a key name followed by `=` after a comma starts the next field.
A term SHALL have 1 to 64 characters, a means 1 to 300, and a next step at most 200, and a call SHALL give at most 6 options.
WHEN the command receives `--option`, it SHALL also set the item's reply terms to the option terms, so that no older list stays beside the options.
WHEN the command receives `--clear-options`, it SHALL set the options and the reply terms to empty lists, unless the same call gives `--reply-term`, in either flag order.
IF the command receives `--option` together with `--reply-term`, or `--clear-options` together with `--option`, THEN it SHALL exit with status 2 and write nothing.
IF an option spec is malformed or breaks a limit, THEN the command SHALL exit with status 2 and write nothing.

#### Scenario: Replace and clear
- **WHEN** the command receives two options, then one option, then `--clear-options`, and then `--clear-options` with `--reply-term` in either order
- **THEN** the item holds the two options and their two terms, then the one option and its term, then empty lists for both, then no options and the one given term, and a comma inside a value is kept
- Proven by `test_option_given_once_or_more_replaces_the_whole_list_and_clear_options_empties_it`

#### Scenario: Refusals
- **WHEN** the command receives a spec with no term, no means, a repeated key, an unknown first key, an over-long field, seven options, or a conflicting flag pair
- **THEN** the command exits with status 2, publish does not run, and the file is unchanged
- Proven by `test_a_bad_option_or_a_conflicting_flag_exits_2_before_anything_is_written`

### Requirement: Warn when an ask is not held
WHEN publish returns and the item's key is a task in the new iteration, the command SHALL read the last stored revision of the item.
IF that revision is not done, has options or reply terms, and is not held for the captain, THEN the command SHALL print a warning on stderr that names the key and the number of options and names the hold command.
The command SHALL exit with status 0 after the warning.

#### Scenario: Read-back reasons
- **WHEN** the last revision asks and is not held, asks through reply terms only, is held, is done, asks nothing, or belongs to a key outside the collection
- **THEN** the command warns for the first two, in the third to fifth cases prints no ask warning, and in the last case prints only the missing-task warning
- Proven by `test_an_ask_that_is_not_held_warns_on_stderr_and_a_held_or_finished_one_does_not`

#### Scenario: Earlier iteration
- **WHEN** the ask is stored in an earlier iteration and the new iteration holds no revision for it
- **THEN** the command still warns that the ask is not held
- Proven by `test_an_ask_that_is_not_held_warns_on_stderr_and_a_held_or_finished_one_does_not`

#### Scenario: Real publish
- **WHEN** the command gives an item that has a bare reply term a problem and two options against the real publish command, first for a task that is not held and then for the same task held, and then clears the options
- **THEN** publish stores the problem and the option terms as the reply terms, the first call warns, the second call prints no warning, and the cleared revision has no options and no reply terms
- Proven by `test_against_the_real_publish_options_derive_the_terms_and_the_warning_stops_once_held`

