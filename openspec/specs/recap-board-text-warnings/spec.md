# recap-board-text-warnings Specification

## Purpose
The Fleet Recap board flags open tasks whose summary is missing, too short, or names a ticket or MR without a matching link.
The flags tell the first mate which recap text needs attention before the captain reads it.
## Requirements
### Requirement: No summary warning
WHILE an open task has no summary, the board SHALL flag the task with a "no summary" warning.
Test: `tests/fm-recap-publish.test.sh` - test_text_warnings_flag_each_open_task_and_leave_a_clean_one_alone

#### Scenario: Missing summary
- **WHEN** an in-flight task has an empty summary
- **THEN** its row shows "no summary" and its panel shows the warning

### Requirement: Short summary warning
WHILE an open task's summary has fewer than 25 words, and the task does not have both a problem and options, the board SHALL flag the task with a "short summary" warning.
Test: `tests/fm-recap-publish.test.sh` - test_text_warnings_flag_each_open_task_and_leave_a_clean_one_alone; test_the_ask_warnings_flag_each_gap_and_leave_a_complete_ask_alone

#### Scenario: Ten-word summary
- **WHEN** an open task has a summary of 10 words
- **THEN** its row shows "short summary"

#### Scenario: Problem and options carry the detail
- **WHEN** an open task has a three-word summary, a problem, and options
- **THEN** its row shows no "short summary" warning

### Requirement: Unlinked reference warning
WHILE an open task's summary, problem, or option meanings name a ticket key or MR reference with no matching link, the board SHALL flag an "unlinked ref" warning.
Test: `tests/fm-recap-publish.test.sh` - test_text_warnings_flag_each_open_task_and_leave_a_clean_one_alone; test_the_ask_warnings_flag_each_gap_and_leave_a_complete_ask_alone

#### Scenario: MR without a link
- **WHEN** an open task's summary names !12 and the task has no link with code !12
- **THEN** its row shows "unlinked ref"

#### Scenario: MR in the problem and an option meaning
- **WHEN** an open task's problem names !77, an option meaning names !78, and the task has neither link
- **THEN** its panel names !77 and !78 in the "unlinked ref" warning

### Requirement: Clean task
WHILE an open task has a summary of 25 words or more with every reference linked, the board SHALL show no text warning for it.
Test: `tests/fm-recap-publish.test.sh` - test_text_warnings_flag_each_open_task_and_leave_a_clean_one_alone

#### Scenario: Clean summary
- **WHEN** an open task has a 30-word summary that names EXAMPLE-7 and has a EXAMPLE-7 link
- **THEN** its row shows no text warning

### Requirement: Done tasks are exempt
WHILE a task is done, the board SHALL show no text warning for it.
Test: `tests/fm-recap-publish.test.sh` - test_text_warnings_flag_each_open_task_and_leave_a_clean_one_alone

#### Scenario: Finished task
- **WHEN** a done task has no summary
- **THEN** its row shows no text warning

### Requirement: Attention count
WHILE open tasks have text warnings, the list SHALL show how many open tasks need text attention.
Test: `tests/fm-recap-publish.test.sh` - test_text_warnings_flag_each_open_task_and_leave_a_clean_one_alone

#### Scenario: Three flagged tasks
- **WHEN** three open tasks have text warnings
- **THEN** the list shows "3 open tasks need text attention"

### Requirement: Ticket key pattern source
WHERE `config/recap-ticket-url` is set, the unlinked reference check SHALL find ticket keys with that setting's key pattern.
Test: `tests/fm-recap-publish.test.sh` - test_the_ticket_key_warning_uses_the_recap_ticket_setting_only

#### Scenario: Custom pattern
- **WHEN** the setting's second line matches ZZ-3 and an open summary names ZZ-3 without a link
- **THEN** the task shows "unlinked ref"

### Requirement: No ticket key check without the setting
WHERE `config/recap-ticket-url` is absent, the unlinked reference check SHALL check no ticket keys.
Test: `tests/fm-recap-publish.test.sh` - test_the_ticket_key_warning_uses_the_recap_ticket_setting_only

#### Scenario: No setting
- **WHEN** no ticket URL setting exists and an open summary names EXAMPLE-7 without a link
- **THEN** the task shows no "unlinked ref" warning for EXAMPLE-7

### Requirement: No problem warning
WHILE an open task has options or reply terms and has no problem, the board SHALL flag the task with a "no problem" warning.
Test: `tests/fm-recap-publish.test.sh` - test_the_ask_warnings_flag_each_gap_and_leave_a_complete_ask_alone

#### Scenario: Ask without a problem
- **WHEN** an open task has options and no problem
- **THEN** its row shows "no problem"

### Requirement: Option without meaning warning
WHILE an open task has an option or a reply term with no meaning, the board SHALL flag the task with an "option without meaning" warning that names each such term.
Test: `tests/fm-recap-publish.test.sh` - test_the_ask_warnings_flag_each_gap_and_leave_a_complete_ask_alone

#### Scenario: One option lacks a meaning
- **WHEN** an open task has the options go-a with a meaning and go-b with an empty meaning
- **THEN** the panel warning names go-b and does not name go-a

### Requirement: Ask that is not held warning
WHILE an open task has options or reply terms and the backlog does not hold it for the captain, the board SHALL flag the task with an "asks but not held" warning.
Test: `tests/fm-recap-publish.test.sh` - test_the_ask_warnings_flag_each_gap_and_leave_a_complete_ask_alone; test_an_ask_that_is_not_held_still_shows_its_call_and_a_task_with_no_ask_shows_none

#### Scenario: Ask without a hold
- **WHEN** an open task has options and the backlog does not hold it for the captain
- **THEN** its row shows "asks but not held" and its panel names the hold command

### Requirement: Held task with no call warning
WHILE an open task is held for the captain and has no options and no reply terms, the board SHALL flag the task with a "held with no call" warning.
Test: `tests/fm-recap-publish.test.sh` - test_the_ask_warnings_flag_each_gap_and_leave_a_complete_ask_alone

#### Scenario: Hold without options
- **WHEN** an open task is held for the captain and has no options and no reply terms
- **THEN** its row shows "held with no call"

### Requirement: Complete ask is clean
WHILE an open task has a problem, options that each have a meaning, and a hold for the captain, the board SHALL show no text warning for it.
Test: `tests/fm-recap-publish.test.sh` - test_the_ask_warnings_flag_each_gap_and_leave_a_complete_ask_alone

#### Scenario: Complete ask
- **WHEN** a held open task has a problem, a three-word summary, and options with meanings
- **THEN** its row and its panel show no warning

### Requirement: Finished ask is exempt
WHILE a task is done, the board SHALL show none of the ask warnings for it.
Test: `tests/fm-recap-publish.test.sh` - test_the_ask_warnings_flag_each_gap_and_leave_a_complete_ask_alone

#### Scenario: Done task with reply terms
- **WHEN** a done task has reply terms and no problem
- **THEN** its row shows no warning

