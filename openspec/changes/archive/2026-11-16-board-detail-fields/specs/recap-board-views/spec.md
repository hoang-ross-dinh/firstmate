## ADDED Requirements

### Requirement: Problem and options fields
WHEN a recap entry has a `problem` string of 600 characters or fewer, the publish command SHALL store it on the task revision.
WHEN a recap entry has an `options` list of 1 to 6 items, the publish command SHALL store each option with a term, a means, and a next step.
An option SHALL have a term of 1 to 64 characters, and it MAY have a means of 300 characters or fewer and a next step of 200 characters or fewer.
The command SHALL store an empty string for a means or next step that the entry omits.
Test: `tests/fm-recap-publish.test.sh` - test_problem_and_options_are_stored_in_one_shape_and_derive_the_reply_terms

#### Scenario: Stored in one shape
- **WHEN** a recap gives task "a" a problem and two options, the second without a next step
- **THEN** the revision of "a" stores the problem and both options with a means and a next step, the second next step being an empty string

#### Scenario: Term alone
- **WHEN** a recap gives task "b" one option that holds only a term
- **THEN** the revision of "b" stores that option with an empty means and an empty next step

#### Scenario: Neither field
- **WHEN** a recap gives task "c" no problem and no options
- **THEN** the revision of "c" stores neither field

### Requirement: Options derive the reply terms
WHILE a task has options, the publish command SHALL store the option terms in order as the reply terms of the revision.
The options SHALL win over a reply_terms list that the same entry sends.
Test: `tests/fm-recap-publish.test.sh` - test_problem_and_options_are_stored_in_one_shape_and_derive_the_reply_terms

#### Scenario: Stale reply terms
- **WHEN** a recap entry sends two options and a reply_terms list with another term
- **THEN** the revision stores the two option terms as its reply terms

### Requirement: Problem and options keep their value
WHEN a recap omits the problem or the options, the publish command SHALL keep the last stored value.
WHEN a recap sends an empty problem, the command SHALL clear the problem.
WHEN a recap sends an empty options list, the command SHALL clear the options and the reply terms that they produced.
Test: `tests/fm-recap-publish.test.sh` - test_problem_and_options_are_stored_in_one_shape_and_derive_the_reply_terms; test_an_empty_options_list_and_an_empty_problem_clear_them_and_the_terms_they_made

#### Scenario: Omitted
- **WHEN** the same recap is published again, and then a recap that names only a summary
- **THEN** the first publish stores no revision for the task, and the second keeps the problem, the options, and the reply terms

#### Scenario: Cleared
- **WHEN** a recap sends an empty options list, and later an empty problem
- **THEN** the first revision drops the options and the reply terms and keeps the problem, and the second drops the problem

### Requirement: Invalid problem or option
IF a problem is not a string of 600 characters or fewer, or an options list is not an array of 6 items or fewer, or an option is not an object with a term of 1 to 64 characters, a means of 300 characters or fewer, and a next step of 200 characters or fewer, THEN the publish command SHALL store nothing and name the task key and the field.
Test: `tests/fm-recap-publish.test.sh` - test_a_bad_problem_or_option_publishes_nothing_and_names_the_field

#### Scenario: Bad values
- **WHEN** a recap sends a problem of 601 characters, seven options, an option with an empty term, or a means of 301 characters
- **THEN** the publish writes no iteration and names the failing field, such as options[1].term

### Requirement: Restore keeps problem and options
WHEN the publish command restores a recap from the log, it SHALL write the problem and the options of the last revision of each task.
A restored recap SHALL publish with no change.
Test: `tests/fm-recap-publish.test.sh` - test_restore_keeps_problem_and_options_and_the_restored_recap_publishes_no_change

#### Scenario: Round trip
- **WHEN** a recap with a problem and options is published, restored, and published again
- **THEN** the restored file holds the problem and the options, and the second publish stores no revision

### Requirement: Problem before summary before call
WHERE a task has a problem, the panel SHALL show the problem under a Problem label before the summary, and SHALL label the summary Finding.
The panel SHALL show the Your call section after the summary.
Test: `tests/fm-recap-publish.test.sh` - test_the_panel_shows_problem_then_summary_then_each_option_with_its_meaning_and_next_step

#### Scenario: Panel order
- **WHEN** the captain opens a task that has a problem, a summary, and options
- **THEN** the panel shows Problem, the problem, Finding, the summary, and Your call in that order

### Requirement: Your call for every ask
WHILE a task has options or reply terms, the panel SHALL show a Your call section with the answer form, whether or not the backlog holds the task for the captain.
WHILE a task has no options, no reply terms, and no hold, the panel SHALL show no Your call section.
Test: `tests/fm-recap-publish.test.sh` - test_an_ask_that_is_not_held_still_shows_its_call_and_a_task_with_no_ask_shows_none

#### Scenario: Ask that is not held
- **WHEN** the captain opens a task with options that the backlog does not hold
- **THEN** the panel shows Your call with the answer form for that task

#### Scenario: No ask
- **WHEN** the captain opens a task with no options, no reply terms, and no hold
- **THEN** the panel shows no Your call section

### Requirement: Option meaning and next step
The Your call section SHALL show each option with its term, its meaning, and its next step when it has one.
An option that has only a term SHALL show only the term.
WHEN the captain picks an option and sends the answer, the board SHALL queue the option term as the selection.
Test: `tests/fm-recap-publish.test.sh` - test_the_panel_shows_problem_then_summary_then_each_option_with_its_meaning_and_next_step; test_a_main_home_card_still_offers_its_reply_terms_and_the_comment_box

#### Scenario: Two options
- **WHEN** the captain opens a task whose first option has a next step and whose second has none
- **THEN** the panel shows both meanings and one next step, and picking the first option queues its term

### Requirement: Hold reason closed by default
WHERE a task shows the Your call section and the backlog gives a hold reason, the panel SHALL show the hold reason in a section that is closed until the captain opens it.
Test: `tests/fm-recap-publish.test.sh` - test_the_hold_reason_is_closed_by_default_and_opens_on_request

#### Scenario: Open the hold reason
- **WHEN** the captain opens a held task and then selects Show hold reason
- **THEN** the hold reason is hidden at first and visible after the selection

### Requirement: Problem and options read as text in the history
WHEN a revision changes the problem or the options, the history SHALL show the change as readable text with no raw JSON.
Test: `tests/fm-recap-publish.test.sh` - test_a_changed_problem_or_option_list_reads_as_text_in_the_history

#### Scenario: New fields
- **WHEN** a revision adds a problem and two options to a task that had neither
- **THEN** the history shows each change as text, with the options listed by term, means, and next step
