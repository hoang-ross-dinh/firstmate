# recap-board-answers Specification

## Purpose
The first mate publishes a full answer to a board comment with the recap.
The board shows the answer in the task history and keeps the newest answer in a Last response section of the task panel.
## Requirements
### Requirement: Answer field
The publish command SHALL accept one answer per task, with a comment id and non-blank text of at most 20000 characters.
Test: `tests/fm-recap-publish.test.sh` - test_a_bad_answer_publishes_nothing_and_the_size_cap_holds

#### Scenario: Valid answer
- **WHEN** a recap gives task "a" an answer to comment "1700000000-abc" with Markdown text
- **THEN** the publish succeeds

### Requirement: Invalid answer
IF an answer has a bad comment id, blank text, or text over 20000 characters, THEN the command SHALL publish nothing.
Test: `tests/fm-recap-publish.test.sh` - test_a_bad_answer_publishes_nothing_and_the_size_cap_holds

#### Scenario: Text too long
- **WHEN** an answer holds 20001 characters
- **THEN** the log is unchanged and the command exits non-zero

### Requirement: Answer stored once
The command SHALL store an answer only on the revision of the publish that sends it.
Test: `tests/fm-recap-publish.test.sh` - test_an_answer_is_stored_only_on_the_revision_of_the_publish_that_sends_it

#### Scenario: Not carried forward
- **WHEN** a publish sends an answer for task "a" and a later publish changes the title of "a"
- **THEN** the later revision holds no answer

### Requirement: Answer alone makes a revision
WHEN a task's only change is a new answer, the command SHALL store a revision for that task.
Test: `tests/fm-recap-publish.test.sh` - test_an_answer_is_stored_only_on_the_revision_of_the_publish_that_sends_it

#### Scenario: Answer only
- **WHEN** a recap adds an answer to task "a" and changes nothing else
- **THEN** the new iteration holds a revision for "a" with that answer

### Requirement: Repeated answer
WHEN a publish repeats a task's last answer unchanged, the command SHALL store no revision for that answer.
Test: `tests/fm-recap-publish.test.sh` - test_an_answer_is_stored_only_on_the_revision_of_the_publish_that_sends_it

#### Scenario: Identical resend
- **WHEN** the first mate sends the same answer for task "a" twice
- **THEN** the second iteration holds no revision

### Requirement: Answer for an unknown task
IF an answer names a task key that is not on the board, THEN the command SHALL ignore that answer.
Test: `tests/fm-recap-publish.test.sh` - test_an_answer_is_stored_only_on_the_revision_of_the_publish_that_sends_it

#### Scenario: Orphan answer
- **WHEN** a recap holds an answer for the key "unknown"
- **THEN** the publish succeeds and stores no revision for "unknown"

### Requirement: Answer history item
WHEN a revision holds an answer, its history card SHALL show a "First mate answer to comment" item with the answer text.
Test: `tests/fm-recap-publish.test.sh` - test_an_answer_renders_in_history_linked_to_its_comment_and_once_only

#### Scenario: Answer in history
- **WHEN** iteration 5 stored an answer to comment "n1" for task "a"
- **THEN** the iteration 5 card of "a" shows "First mate answer to comment n1" once

### Requirement: Link to the answered comment
WHERE the answered comment is on the board, the answer item SHALL link to that comment.
Test: `tests/fm-recap-publish.test.sh` - test_an_answer_renders_in_history_linked_to_its_comment_and_once_only

#### Scenario: Comment on the board
- **WHEN** comment "n1" is shown in the panel
- **THEN** selecting the comment id in the answer item moves to comment "n1"

### Requirement: Answered comment not on the board
WHERE the answered comment is not on the board, the answer item SHALL name the comment id without a link.
Test: `tests/fm-recap-publish.test.sh` - test_an_answer_for_a_comment_not_on_the_board_names_its_note_without_a_link

#### Scenario: Comment missing
- **WHEN** the answer names comment "n9" and the board has no comment "n9"
- **THEN** the answer item shows "n9" as plain text

### Requirement: Inert answer Markdown
The board SHALL render answer Markdown so that no markup or script from the answer runs.
Test: `tests/fm-recap-publish.test.sh` - test_hostile_answer_markdown_renders_inert; test_hostile_markdown_in_the_last_response_renders_inert

#### Scenario: Script in an answer
- **WHEN** an answer holds a script tag and a `javascript:` link
- **THEN** the board shows them as text and runs no script

### Requirement: Answer after a poll
WHEN a poll brings a new answer, the page SHALL show it and keep the open panel, its scroll position, and focus.
Test: `tests/fm-recap-publish.test.sh` - test_an_answer_appears_after_a_poll_without_losing_the_open_panel_or_focus

#### Scenario: New answer while open
- **WHEN** the panel of task "a" is open and a publish adds an answer to "a"
- **THEN** the panel shows the answer after the next poll and stays open

### Requirement: Last response shows the newest answer
The panel SHALL show a Last response section that holds the task's newest answer from any revision, unless a later revision changed the summary.
Test: `tests/fm-recap-publish.test.sh` - test_the_last_response_keeps_the_answer_after_a_publish_that_omits_it

#### Scenario: Answer kept
- **WHEN** iteration 4 stored an answer for task "a" and iteration 5 changed "a" without an answer and without changing its summary
- **THEN** the Last response section of "a" shows the iteration 4 answer

### Requirement: Newer answer replaces the older
WHEN a newer answer arrives for a task, the Last response section SHALL show the newer answer in place of the older one.
Test: `tests/fm-recap-publish.test.sh` - test_a_newer_answer_replaces_the_older_one_in_the_last_response

#### Scenario: Second answer
- **WHEN** task "a" has answers from iterations 4 and 6
- **THEN** the Last response section shows only the iteration 6 answer

### Requirement: Reply fallback
WHILE a task has no answer, the Last response section SHALL show the newest comment reply.
Test: `tests/fm-recap-publish.test.sh` - test_the_last_response_falls_back_to_the_newest_reply_only_without_an_answer

#### Scenario: Reply only
- **WHEN** task "a" has no answer and two replied comments
- **THEN** the Last response section shows the newer reply

### Requirement: Hidden when empty
WHILE a task has no answer and no comment reply, the panel SHALL hide the Last response section.
Test: `tests/fm-recap-publish.test.sh` - test_the_last_response_section_is_hidden_when_the_task_has_no_answer_and_no_reply

#### Scenario: Nothing to show
- **WHEN** task "a" has no answer and no reply
- **THEN** the panel has no Last response section

### Requirement: Last response position
The panel SHALL place the Last response section directly above the Comment section.
Test: `tests/fm-recap-publish.test.sh` - test_the_last_response_section_sits_directly_above_the_comment_section

#### Scenario: Section order
- **WHEN** task "a" has an answer
- **THEN** the Last response section is the section directly before the Comment section

### Requirement: Iteration stamp outside the window
WHILE the answer's iteration is outside the display window, the Last response section SHALL show the iteration number instead of a time.
Test: `tests/fm-recap-publish.test.sh` - test_the_last_response_shows_the_iteration_when_the_answer_time_is_out_of_the_window

#### Scenario: Old answer
- **WHEN** the newest answer of task "a" is from iteration 2 and iteration 2 is outside the window
- **THEN** the section stamps the answer "iteration 2"

### Requirement: Last response after a poll
WHEN a poll brings a newer last response, the page SHALL show it and keep the scroll position, focus, and any unsent comment text.
Test: `tests/fm-recap-publish.test.sh` - test_a_poll_updates_the_last_response_keeping_scroll_focus_and_an_unsent_comment

#### Scenario: Unsent comment
- **WHEN** the captain has unsent comment text and a newer answer is published
- **THEN** the page keeps the comment text and shows the newer answer after the text is sent or cleared

### Requirement: Stale answer hides the section
WHEN a revision newer than the newest answer holds a different summary from the revision that stored the answer, the panel SHALL hide the Last response section.
The section SHALL stay hidden when a comment reply exists, because a reply has no time to compare with the summary change.
History and the comment list SHALL still show the answer and the replies.
WHEN a publish changes the summary and sends an answer together, the panel SHALL show that answer.
Test: `tests/fm-recap-publish.test.sh` - test_the_last_response_hides_an_answer_the_summary_has_moved_past
Test: `tests/fm-recap-publish.test.sh` - test_a_stale_answer_does_not_fall_back_to_an_older_comment_reply

#### Scenario: Summary moved on
- **WHEN** iteration 4 stored an answer for task "a" and iteration 5 changed the summary of "a"
- **THEN** the panel of "a" has no Last response section and History still lists the answer

#### Scenario: Answer sent with the change
- **WHEN** iteration 6 changes the summary of "a" and sends an answer in the same publish
- **THEN** the Last response section shows the iteration 6 answer

