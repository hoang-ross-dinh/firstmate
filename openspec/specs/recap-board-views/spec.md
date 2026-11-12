# recap-board-views Specification

## Purpose
The Fleet Recap board shows each iteration as theme groups of task rows, with filters, badges, and a task detail panel.
The panel shows the task's current state and its full revision history.
## Requirements
### Requirement: Theme groups
The iteration view SHALL group task rows by theme code.
Test: `tests/fm-recap-publish.test.sh` - test_the_iteration_view_groups_by_theme_and_marks_each_task

#### Scenario: Two themes
- **WHEN** the captain opens an iteration with tasks in themes AA and ZZ
- **THEN** the view shows one group for AA and one group for ZZ

### Requirement: New or unchanged mark
The iteration view SHALL mark each row as new in this iteration or unchanged since the iteration of its last revision.
Test: `tests/fm-recap-publish.test.sh` - test_the_iteration_view_groups_by_theme_and_marks_each_task

#### Scenario: Unchanged row
- **WHEN** task A last changed in iteration 2 and the captain views iteration 3
- **THEN** the row for A reads "unchanged since iteration 2"

### Requirement: Priority order
The iteration view SHALL order rows and groups by priority emoji: red, then yellow, then green, then any other.
Test: `tests/fm-recap-publish.test.sh` - test_rows_and_groups_are_ordered_by_priority_emoji

#### Scenario: Group with a red row first
- **WHEN** group ZZ holds a red row and group AA holds only green rows
- **THEN** the view lists ZZ before AA

### Requirement: Row tie order
WHEN two rows in a group have equal priority, the iteration view SHALL put a waiting row first, then order by title.
Test: none

#### Scenario: Waiting row first
- **WHEN** two green rows exist and only the second is waiting on the captain
- **THEN** the waiting row comes first

### Requirement: Group tie order
WHEN two groups have equal priority, the iteration view SHALL order them alphabetically with the misc group last.
Test: none

#### Scenario: Misc last
- **WHEN** groups AA, misc, and ZZ all hold only green rows
- **THEN** the view lists AA, ZZ, then misc

### Requirement: Filters
The iteration view SHALL offer the filters Open, Changed in this iteration, Waiting on you, and All, each with its count.
Test: `tests/fm-recap-publish.test.sh` - test_the_filters_narrow_the_iteration_view

#### Scenario: Waiting filter
- **WHEN** the captain selects "Waiting on you" and one task waits on the captain
- **THEN** the view lists only that task and the chip reads "Waiting on you (1)"

### Requirement: Iteration navigation
The board SHALL let the reader move between the last 30 iterations.
Test: `tests/fm-recap-publish.test.sh` - test_the_captain_can_move_between_iterations; test_the_display_window_keeps_the_last_30_iterations_and_every_revision_full

#### Scenario: Previous iteration
- **WHEN** the captain views iteration 3 of 3 and selects the previous control
- **THEN** the view shows iteration 2 of 3

### Requirement: Full revision history in the payload
The board payload SHALL keep every revision of every task in full.
Test: `tests/fm-recap-publish.test.sh` - test_the_display_window_keeps_the_last_30_iterations_and_every_revision_full

#### Scenario: Older revisions
- **WHEN** a task has revisions older than the 30 navigable iterations
- **THEN** the payload holds those revisions in full with no one-line summary form

### Requirement: Finished tasks age out of Open
WHILE a task has been done for more than 3 iterations, the Open filter SHALL hide the task.
Test: `tests/fm-recap-publish.test.sh` - test_a_finished_task_stays_three_iterations_then_hides_but_remains_reachable

#### Scenario: Fourth iteration
- **WHEN** task A became done in iteration 1 and the captain views iteration 4
- **THEN** the Open filter does not list task A

### Requirement: Hidden tasks stay reachable
WHILE a done task is hidden from Open, the All filter SHALL list the task with a hidden badge.
Test: `tests/fm-recap-publish.test.sh` - test_a_finished_task_stays_three_iterations_then_hides_but_remains_reachable

#### Scenario: All filter
- **WHEN** the captain selects All after task A aged out
- **THEN** the view lists task A with a "hidden" badge

### Requirement: Waiting badge
WHILE a task waits on the captain, its row SHALL show a "waiting on you" badge.
Test: none

#### Scenario: Held task
- **WHEN** a task is held for the captain
- **THEN** its row shows "waiting on you"

### Requirement: Blocked badge
WHILE a task has blockers, the row and the panel SHALL show a blocked badge and name the blockers.
Test: `tests/fm-recap-publish.test.sh` - test_a_blocked_task_shows_a_blocked_badge_and_its_blockers_and_an_unblocked_task_shows_none; test_a_secondmate_home_task_with_blockers_shows_the_blocked_badge

#### Scenario: Blocked task
- **WHEN** task A is blocked by task B
- **THEN** the row and the panel for A show "blocked" and "blocked by B"

#### Scenario: Unblocked task
- **WHEN** task C has no blockers
- **THEN** the row and the panel for C show no blocked badge

### Requirement: On Hold badge
WHILE a task has on-hold text, the row and the panel SHALL show an On Hold badge and the on-hold text.
Test: `tests/fm-recap-publish.test.sh` - test_an_on_hold_task_shows_an_on_hold_badge_and_its_event_and_an_unmarked_task_shows_none; test_a_task_both_blocked_and_on_hold_shows_both_badges

#### Scenario: On-hold task
- **WHEN** task A has on-hold text "waiting: first review feedback"
- **THEN** the row and the panel for A show "On Hold" and that text

#### Scenario: Blocked and on hold
- **WHEN** task A is blocked and has on-hold text
- **THEN** the row shows both the blocked badge and the On Hold badge

### Requirement: On-hold text is inert
The board SHALL show on-hold text as plain text and show its history change as readable text.
Test: `tests/fm-recap-publish.test.sh` - test_the_on_hold_text_is_escaped_and_a_history_change_reads_as_text

#### Scenario: Markup in on-hold text
- **WHEN** the on-hold text holds an HTML tag
- **THEN** the board shows the tag as text and runs no markup

### Requirement: State badge tone
The panel state badge SHALL use the same tone as the row state badge.
Test: `tests/fm-recap-publish.test.sh` - test_the_detail_state_badge_matches_the_row_tone_and_the_theme_code_reads_as_a_recap_label

#### Scenario: In-flight task
- **WHEN** an in-flight task is shown in a row and in the panel
- **THEN** both state badges have the same tone

### Requirement: Recap label
WHERE a task has a summary, an emoji, or a theme other than misc, the panel SHALL show its theme code as a Recap label.
Test: `tests/fm-recap-publish.test.sh` - test_the_detail_state_badge_matches_the_row_tone_and_the_theme_code_reads_as_a_recap_label; test_a_backlog_task_without_a_recap_line_shows_in_open_without_a_recap_badge

#### Scenario: Task with recap content
- **WHEN** a task has theme AA
- **THEN** the panel shows "Recap AA"

#### Scenario: Task with no recap content
- **WHEN** a task has theme misc, no summary, and no emoji
- **THEN** the panel shows no Recap label

### Requirement: Task panel opens over the list
WHEN the reader selects a row, the board SHALL open the task detail as a side panel over the list without moving the list.
Test: `tests/fm-recap-publish.test.sh` - test_a_task_detail_opens_as_a_panel_over_the_list_without_moving_the_list

#### Scenario: Open panel
- **WHEN** the captain selects the row for task A
- **THEN** the panel for A opens and the list keeps its scroll position

### Requirement: Panel close
WHEN the reader selects Close or presses Escape, the board SHALL close the panel and keep the list scroll position.
Test: `tests/fm-recap-publish.test.sh` - test_the_panel_closes_with_its_close_button_or_escape_and_keeps_the_list_scroll

#### Scenario: Escape
- **WHEN** the panel is open and the captain presses Escape
- **THEN** the panel closes and the list is at the same scroll position

### Requirement: Page behind the panel is clipped
WHILE the panel is open, the board SHALL clip the page behind it, so that the panel covers no visible list text.
Test: `tests/fm-recap-publish.test.sh` - test_the_open_panel_clips_the_page_behind_it_so_no_text_is_covered

#### Scenario: Narrow list
- **WHEN** the panel is open
- **THEN** no list text is under the panel

### Requirement: Page keys scroll the panel
WHILE the panel is open and focus is outside an editable field, the board SHALL scroll the panel on PageUp and PageDown.
Test: `tests/fm-recap-publish.test.sh` - test_panel_page_keys_scroll_the_panel_and_leave_editing_keys_to_the_comment_field

#### Scenario: PageDown
- **WHEN** the captain presses PageDown with focus on the panel
- **THEN** the panel scrolls down

### Requirement: Editing keys stay in the field
WHILE focus is in an editable field, the board SHALL leave the editing keys to that field.
Test: `tests/fm-recap-publish.test.sh` - test_panel_page_keys_scroll_the_panel_and_leave_editing_keys_to_the_comment_field

#### Scenario: Keys in the comment box
- **WHEN** the captain presses PageDown in the comment box
- **THEN** the board does not scroll the panel

### Requirement: Pinned panel header
The panel SHALL pin a header that holds the task title and a Close button.
Test: `tests/fm-recap-publish.test.sh` - test_the_panel_header_pins_the_title_and_close_button_and_the_back_link_is_gone

#### Scenario: Scrolled panel
- **WHEN** the captain scrolls the panel down
- **THEN** the title and the Close button stay visible and the panel shows no back link

### Requirement: Fresh load
WHEN the board loads with no saved view, the board SHALL show the list with the panel closed.
Test: `tests/fm-recap-publish.test.sh` - test_a_freshly_loaded_board_starts_with_the_panel_closed_and_the_list_rendered

#### Scenario: First open
- **WHEN** the captain opens the board in a new tab
- **THEN** the list is rendered and no panel is open

### Requirement: Revision history
The panel SHALL show every revision newest first as one card with its changed fields as readable values.
Test: `tests/fm-recap-publish.test.sh` - test_the_task_detail_shows_newest_first_history_with_field_and_note_diffs; test_every_history_revision_is_one_card_with_readable_values

#### Scenario: History cards
- **WHEN** task A has three revisions
- **THEN** the panel shows three cards, newest first, with no raw JSON

### Requirement: Note diff
WHEN a revision changed the task note, its history card SHALL offer a "Show note diff" button.
Test: `tests/fm-recap-publish.test.sh` - test_the_task_detail_shows_newest_first_history_with_field_and_note_diffs

#### Scenario: Note change
- **WHEN** the newest revision of task A changed its note
- **THEN** that card offers "Show note diff"

### Requirement: Ticket key links
WHERE `config/recap-jira-base` holds an https prefix, the panel SHALL link each ticket key in the task text to that prefix.
Test: `tests/fm-recap-publish.test.sh` - test_a_jira_key_links_only_through_the_private_base_setting

#### Scenario: Base set
- **WHEN** the base is `https://tracker.example.invalid/browse/` and the title names EXAMPLE-7
- **THEN** the panel links EXAMPLE-7 to `https://tracker.example.invalid/browse/EXAMPLE-7`

### Requirement: Ticket keys without a base
WHERE `config/recap-jira-base` is absent, the panel SHALL show ticket keys as plain text.
Test: `tests/fm-recap-publish.test.sh` - test_a_jira_key_links_only_through_the_private_base_setting

#### Scenario: No base
- **WHEN** no base is set and the title names EXAMPLE-7
- **THEN** the panel shows EXAMPLE-7 without a link

### Requirement: Collection warnings
The board SHALL list collection warnings in their own section, outside the task counts.
Test: `tests/fm-recap-publish.test.sh` - test_warnings_have_their_own_section_and_never_count_as_work

#### Scenario: One warning
- **WHEN** a publish records one collection warning
- **THEN** the board shows it in the warnings section and the filter counts are unchanged

### Requirement: Header never covers the first filter chip
WHILE the viewport is 1024 px wide or narrower, the board SHALL let the page header scroll away with the list, so that no header control paints over the first filter chip.
Test: `tests/fm-recap-publish.test.sh` - test_the_nav_never_paints_over_the_first_filter_chip_at_compact_widths

#### Scenario: Scrolling the list at a compact width
- **WHEN** the captain scrolls the list at a viewport 600 px wide, where the header wraps onto two rows
- **THEN** no opaque header surface is over the text of the first filter chip at any scroll position

