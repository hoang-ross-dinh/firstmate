## ADDED Requirements

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
