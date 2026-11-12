## MODIFIED Requirements

### Requirement: Link kinds
The publish command SHALL accept task links of kind ticket, mr, slack, doc, and report, each with a code and an http or https URL, except that a report MAY omit the URL.
Test: `tests/fm-recap-publish.test.sh` - test_publish_accepts_links_and_stores_them_only_when_present_or_changed; test_slack_and_doc_links_are_accepted_stored_and_rendered; test_a_report_link_needs_no_url_but_a_given_url_must_be_http

#### Scenario: Slack and doc links
- **WHEN** a recap gives task "a" a slack link and a doc link
- **THEN** the publish succeeds and the revision of "a" stores both links

#### Scenario: Report with no URL
- **WHEN** a recap gives task "a" a report link with a path as its code and no url
- **THEN** the publish succeeds and the revision of "a" stores the link as sent

#### Scenario: Report with a bad URL
- **WHEN** a report link has the url `javascript:alert(1)`
- **THEN** the publish stores nothing and names the link field

### Requirement: Row link chips
The board SHALL show each task's links as chips beside its row, except links of kind report.
Test: `tests/fm-recap-publish.test.sh` - test_rows_show_link_chips_and_the_panel_shows_a_references_section; test_a_report_link_shows_as_its_own_references_group_with_no_row_chip

#### Scenario: Chips on the row
- **WHEN** task "a" has a ticket link EXAMPLE-7 and an MR link !12
- **THEN** the row of "a" shows two chips, EXAMPLE-7 and !12

#### Scenario: Report on the row
- **WHEN** task "a" has an MR link and a report link
- **THEN** the row of "a" shows one chip, for the MR

### Requirement: Grouped panel section
The panel SHALL show a "References" section that groups links under Tickets, MRs, Slack, Docs, and Reports, and omits each empty group.
A report with no URL SHALL show its path as plain text, and a report with an http or https URL SHALL show a hyperlink.
Test: `tests/fm-recap-publish.test.sh` - test_rows_show_link_chips_and_the_panel_shows_a_references_section; test_a_task_with_only_one_link_kind_shows_only_that_group; test_a_report_link_shows_as_its_own_references_group_with_no_row_chip

#### Scenario: One kind only
- **WHEN** task "a" has only MR links
- **THEN** the section shows the MRs group and no other group

#### Scenario: Report path
- **WHEN** task "a" has a report link with no url
- **THEN** the section shows a Reports group holding the path as plain text with no hyperlink

## ADDED Requirements

### Requirement: Report line becomes a report link
WHEN a task summary holds a stand-alone line of the form "Report: <path>", the command SHALL remove that line from the stored summary and store a report link whose code is the path.
The path SHALL have 64 characters or fewer and no whitespace, otherwise the line SHALL stay in the summary.
Test: `tests/fm-recap-publish.test.sh` - test_a_report_line_in_the_summary_becomes_a_report_link_and_leaves_the_summary

#### Scenario: Lifted line
- **WHEN** the summary of task "a" has the line `Report: data/synthetic-task/report.md` between two other lines
- **THEN** the stored summary holds the other two lines and the links of "a" end with that report path

#### Scenario: Line kept
- **WHEN** the line holds a path longer than 64 characters, or the text "Report:" sits inside a sentence
- **THEN** the summary is stored unchanged and no report link is added

### Requirement: Lifted report link is not duplicated
WHEN a task already has a link with the lifted path as its code, the command SHALL add no second link.
The command SHALL place a lifted link after the explicit links and before derived ticket chips.
Test: `tests/fm-recap-publish.test.sh` - test_a_report_line_does_not_duplicate_an_explicit_report_link_and_goes_before_derived_chips

#### Scenario: Explicit link exists
- **WHEN** the recap sends an explicit report link and a summary line with the same path
- **THEN** the task holds one report link, the explicit one, and the summary has no Report line

### Requirement: Stable report lift
WHEN a republish carries the same Report line, the command SHALL store no new revision.
Test: `tests/fm-recap-publish.test.sh` - test_a_report_line_in_the_summary_becomes_a_report_link_and_leaves_the_summary

#### Scenario: Republish
- **WHEN** the first mate publishes the same recap twice, or a recap with no entry for the task
- **THEN** the second iteration holds no revision for the task
