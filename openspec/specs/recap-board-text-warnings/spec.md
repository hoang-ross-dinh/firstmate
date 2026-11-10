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
WHILE an open task's summary has fewer than 25 words, the board SHALL flag the task with a "short summary" warning.
Test: `tests/fm-recap-publish.test.sh` - test_text_warnings_flag_each_open_task_and_leave_a_clean_one_alone

#### Scenario: Ten-word summary
- **WHEN** an open task has a summary of 10 words
- **THEN** its row shows "short summary"

### Requirement: Unlinked reference warning
WHILE an open task's summary names a ticket key or MR reference with no matching link, the board SHALL flag an "unlinked ref" warning.
Test: `tests/fm-recap-publish.test.sh` - test_text_warnings_flag_each_open_task_and_leave_a_clean_one_alone

#### Scenario: MR without a link
- **WHEN** an open task's summary names !12 and the task has no link with code !12
- **THEN** its row shows "unlinked ref"

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
