# recap-board-actions Specification

## Purpose
The Fleet Recap task panel lets the captain answer a held task, comment on any task, and order a merge or a dispatch.
Every action travels through the existing answer and inbox routes, so the board adds no new intake.

## Requirements
### Requirement: Main-home hold answer choices
WHILE a main-home task waits on the captain, the panel SHALL offer its reply terms and Reconcile as choices, plus a free-text note.
Test: `tests/fm-recap-publish.test.sh` - test_a_main_home_hold_queues_its_answer_for_the_captain_hold_intake; test_a_main_home_card_still_offers_its_reply_terms_and_the_comment_box (neither asserts the Reconcile choice)

#### Scenario: Held main-home task
- **WHEN** a main-home task waits on the captain with reply terms "merge" and "hold"
- **THEN** the panel offers "merge", "hold", and "Reconcile" as choices and a note field

### Requirement: Main-home answer route
WHEN the captain sends a main-home hold answer, the board SHALL queue it for the captain-hold intake with the task id, choice, and note.
Test: `tests/fm-recap-publish.test.sh` - test_a_main_home_hold_queues_its_answer_for_the_captain_hold_intake

#### Scenario: Queued answer
- **WHEN** the captain picks "merge" on held task "a" and sends it
- **THEN** the board queues one answer for task "a" with the choice "merge"

### Requirement: Second-mate hold answer choices
WHILE a second-mate task waits on the captain, the panel SHALL offer its reply terms and name the home that acts on the answer.
Test: `tests/fm-recap-publish.test.sh` - test_a_secondmate_card_offers_answer_buttons_and_names_who_acts

#### Scenario: Held second-mate task
- **WHEN** a task of second mate "mate1" waits on the captain
- **THEN** the panel offers its reply terms, offers no Reconcile choice, and reads "Answer goes to mate1 through the first mate"

### Requirement: Second-mate answer route
WHEN the captain sends a second-mate hold answer, the capture SHALL create one inbox note tagged as an answer for that task.
Test: `tests/fm-recap-publish.test.sh` - test_a_secondmate_answer_reaches_the_first_mate_as_one_answer_note

#### Scenario: Answer note
- **WHEN** the captain sends "go" with the text "after lunch" on task "x" of second mate "mate1" in iteration 4
- **THEN** the inbox holds one note with the body `[recap task=mate1:x iteration=4 answer] go - after lunch`

### Requirement: Comment box
The panel SHALL offer a comment box for every task.
Test: `tests/fm-recap-publish.test.sh` - test_a_comment_queues_with_the_question_markup_and_shows_its_reply

#### Scenario: Comment on a task that is not held
- **WHEN** the captain opens an in-flight task
- **THEN** the panel shows a comment box

### Requirement: Comment route
WHEN the captain sends a board comment, the capture SHALL create one tagged inbox note and no hold answer.
Test: `tests/fm-recap-publish.test.sh` - test_a_board_comment_becomes_one_tagged_inbox_note_and_no_answer; test_a_comment_that_names_a_task_never_reaches_the_answer_intake

#### Scenario: Comment note
- **WHEN** the captain comments on task "a" in iteration 3
- **THEN** the inbox holds one note whose body starts with `[recap task=a iteration=3]`
- **AND** the captain-hold intake receives nothing

### Requirement: Repeated capture
WHEN the same comment capture is delivered again, the capture SHALL replay the existing note and create no second note.
Test: `tests/fm-recap-publish.test.sh` - test_a_repeated_delivery_of_one_capture_replays_the_same_note

#### Scenario: Duplicate delivery
- **WHEN** one comment capture is delivered twice
- **THEN** the inbox holds one note and the second delivery reports a replay

### Requirement: Comment reply
WHEN a comment note has a reply, the panel SHALL show the reply under its comment.
Test: `tests/fm-recap-publish.test.sh` - test_a_comment_reply_renders_under_its_comment

#### Scenario: Reply shown
- **WHEN** the first mate replies to a board comment and the board is rebuilt
- **THEN** the panel shows the reply under that comment in the Comments section

### Requirement: Merge now button
WHILE a main-home task is not done, has a PR URL, and offers the reply term merge, the panel SHALL show a Merge now button.
Test: `tests/fm-recap-publish.test.sh` - test_merge_and_dispatch_buttons_reuse_the_existing_routes

#### Scenario: Ready PR
- **WHEN** main-home task "a" has a PR URL and the reply term "merge"
- **THEN** the panel shows Merge now and sending it queues `merge.a` with the choice "merge"

#### Scenario: No ready PR
- **WHEN** an in-flight task has no PR URL
- **THEN** the panel shows no Merge now button

### Requirement: Dispatch now button
WHILE a main-home task is queued, the panel SHALL show a Dispatch now button.
Test: `tests/fm-recap-publish.test.sh` - test_merge_and_dispatch_buttons_reuse_the_existing_routes

#### Scenario: Queued task
- **WHEN** main-home task "b" is queued
- **THEN** the panel shows Dispatch now and sending it queues `dispatch.charted` with the choice "b"
