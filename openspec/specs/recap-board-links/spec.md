# recap-board-links Specification

## Purpose
The first mate attaches ticket, MR, chat, and document links to recap tasks.
The board shows them as chips on each row and in a grouped section of the task panel.

## Requirements
### Requirement: Link kinds
The publish command SHALL accept task links of kind ticket, mr, slack, and doc, each with a code and an http or https URL.
Test: `tests/fm-recap-publish.test.sh` - test_publish_accepts_links_and_stores_them_only_when_present_or_changed; test_slack_and_doc_links_are_accepted_stored_and_rendered

#### Scenario: Slack and doc links
- **WHEN** a recap gives task "a" a slack link and a doc link
- **THEN** the publish succeeds and the revision of "a" stores both links

### Requirement: Invalid link entry
IF a link entry is invalid, THEN the command SHALL publish nothing and name the task key and the link field.
Test: `tests/fm-recap-publish.test.sh` - test_publish_refuses_a_bad_link_entry_and_writes_nothing; test_a_validation_error_names_the_task_key_and_the_field

#### Scenario: Bad URL
- **WHEN** the first link of task "a" has the URL `ftp://example.invalid/x`
- **THEN** the log is unchanged and the error names `task a: links[0].url`

### Requirement: Omitted links are kept
WHEN a recap omits the links of a known task, the command SHALL keep the task's last stored links.
Test: `tests/fm-recap-publish.test.sh` - test_publish_accepts_links_and_stores_them_only_when_present_or_changed

#### Scenario: Omitted links
- **WHEN** task "a" has one link and the next recap does not name "a"
- **THEN** the board still shows the link and the publish stores no revision for "a"

### Requirement: Empty list clears links
WHEN a recap sends an empty links list for a task, the command SHALL clear the task's stored links.
Test: `tests/fm-recap-publish.test.sh` - test_publish_accepts_links_and_stores_them_only_when_present_or_changed

#### Scenario: Clear links
- **WHEN** task "a" has one link and the recap sends `"links": []`
- **THEN** the next revision of "a" holds no links

### Requirement: Row link chips
The board SHALL show each task's links as chips beside its row.
Test: `tests/fm-recap-publish.test.sh` - test_rows_show_link_chips_and_the_panel_shows_a_tickets_and_mrs_section

#### Scenario: Chips on the row
- **WHEN** task "a" has a ticket link EXAMPLE-7 and an MR link !12
- **THEN** the row of "a" shows two chips, EXAMPLE-7 and !12

### Requirement: Grouped panel section
The panel SHALL show a "Tickets & MRs" section that groups links under Tickets, MRs, Slack, and Docs, and omits each empty group.
Test: `tests/fm-recap-publish.test.sh` - test_rows_show_link_chips_and_the_panel_shows_a_tickets_and_mrs_section; test_a_task_with_only_one_link_kind_shows_only_that_group

#### Scenario: One kind only
- **WHEN** task "a" has only MR links
- **THEN** the section shows the MRs group and no other group

### Requirement: Safe link rendering
IF a link URL is not http or https, THEN the board SHALL show the link text without a hyperlink.
Test: `tests/fm-recap-publish.test.sh` - test_link_values_are_escaped_and_an_unsafe_url_never_becomes_a_link

#### Scenario: Script URL
- **WHEN** the board data holds a link with a `javascript:` URL
- **THEN** the board shows the link text as plain text with no hyperlink

### Requirement: Links after a poll
WHEN a poll brings new links, the page SHALL show them and keep the scroll position, the open panel, and focus.
Test: `tests/fm-recap-publish.test.sh` - test_links_appear_after_a_poll_without_losing_scroll_panel_or_focus

#### Scenario: New link
- **WHEN** the panel of task "a" is open and a publish adds a link to "a"
- **THEN** the row and the panel show the link after the next poll and the panel stays open

### Requirement: Derived ticket chips
WHERE `config/recap-ticket-url` holds a valid URL template, the command SHALL derive one ticket chip for each distinct ticket key in the task title.
Test: `tests/fm-recap-publish.test.sh` - test_a_title_key_with_no_links_gets_a_derived_chip; test_two_distinct_title_keys_derive_two_chips_in_title_order

#### Scenario: Two keys
- **WHEN** the template is `https://tracker.example.invalid/browse/{key}` and the title names EXAMPLE-1 and EXAMPLE-2
- **THEN** the task gets two ticket chips in title order

### Requirement: No ticket URL setting
WHERE `config/recap-ticket-url` is absent, the command SHALL derive no ticket chips.
Test: `tests/fm-recap-publish.test.sh` - test_no_ticket_url_config_derives_no_chips

#### Scenario: No setting
- **WHEN** no ticket URL setting exists and the title names EXAMPLE-1
- **THEN** the task gets no derived chip

### Requirement: No duplicate derived chip
WHEN an explicit link has the same code as a title key, the command SHALL derive no chip for that key.
Test: `tests/fm-recap-publish.test.sh` - test_an_explicit_link_with_the_same_code_is_not_duplicated_and_stays_first

#### Scenario: Explicit link exists
- **WHEN** the title names EXAMPLE-1 and the recap sends a ticket link with code EXAMPLE-1
- **THEN** the task has one EXAMPLE-1 chip

### Requirement: Derived chips follow explicit links
The command SHALL place derived ticket chips after the task's explicit links.
Test: `tests/fm-recap-publish.test.sh` - test_a_different_explicit_link_stays_first_and_the_derived_chip_follows

#### Scenario: Mixed links
- **WHEN** the recap sends an MR link and the title names EXAMPLE-1
- **THEN** the MR chip comes first and the EXAMPLE-1 chip follows

### Requirement: Custom key pattern
WHERE the ticket URL setting has a second line, the command SHALL use that line as the ticket key pattern.
Test: `tests/fm-recap-publish.test.sh` - test_a_custom_key_regex_on_line_two_is_used

#### Scenario: Custom pattern
- **WHEN** the second line is a pattern that matches ZZ-3 and the title names ZZ-3
- **THEN** the task gets a ZZ-3 chip

### Requirement: Invalid ticket URL setting
IF the ticket URL setting is invalid, THEN the command SHALL warn once and still publish.
Test: `tests/fm-recap-publish.test.sh` - test_a_bad_template_or_regex_warns_once_and_the_publish_succeeds

#### Scenario: Template without a key slot
- **WHEN** the template has no `{key}` placeholder
- **THEN** the publish prints one warning and succeeds with no derived chips

### Requirement: Stable derived chips
WHEN a republish derives the same ticket chips, the command SHALL store no new revision.
Test: `tests/fm-recap-publish.test.sh` - test_republishing_with_derived_chips_makes_no_new_revision

#### Scenario: Republish
- **WHEN** the first mate publishes the same recap twice
- **THEN** the second iteration holds no revision for the task with derived chips
