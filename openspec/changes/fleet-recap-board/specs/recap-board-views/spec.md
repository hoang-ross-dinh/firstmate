## ADDED Requirements

### Requirement: Iteration view grouping and marks
The board SHALL group tasks by theme code in the iteration view.
The iteration view SHALL mark each task as new in this iteration or unchanged since iteration N.

#### Scenario: Theme groups
- **WHEN** the captain opens an iteration containing tasks with theme codes LW and QD
- **THEN** the board shows one group per theme code with its tasks inside

#### Scenario: Change marks
- **WHEN** a task has a revision from the shown iteration, or last changed in iteration 5
- **THEN** the board marks it "new in this iteration" or "unchanged since iteration 5"

### Requirement: Iteration view filters
The iteration view SHALL offer the filters Open, Changed in this iteration, Waiting on you, and All.

#### Scenario: Waiting on you
- **WHEN** the captain selects Waiting on you
- **THEN** the board lists only tasks with an open captain hold

#### Scenario: Changed filter
- **WHEN** the captain selects Changed in this iteration
- **THEN** the board lists only tasks with a revision from the shown iteration

### Requirement: Iteration navigation
The board SHALL let the captain move to the previous and next iteration.

#### Scenario: Previous iteration
- **WHEN** the captain selects previous on iteration 8
- **THEN** the board shows iteration 7 with each task at its revision as of iteration 7

#### Scenario: Newest iteration
- **WHEN** the board shows the newest iteration
- **THEN** the next control is disabled

### Requirement: Task detail history
WHEN the captain opens a task, the board SHALL show the task detail with its history, newest first.
WHEN two revisions of one task differ, the task history SHALL show each changed field with its old and new value.
WHEN a note changed, the task history SHALL offer a diff of the old and new note.

#### Scenario: Field changes
- **WHEN** a revision changed the state from queued to in_flight
- **THEN** the history shows the state field with old value queued and new value in_flight

#### Scenario: Note diff
- **WHEN** a revision changed the note text
- **THEN** the history offers a diff of the old and new note

### Requirement: Display window
The board SHALL show the last 30 iterations of a task's history in full, and each older revision as one line.

#### Scenario: Older revision
- **WHEN** a task has a revision from iteration 2 and the newest iteration is 40
- **THEN** the history shows that revision as one line

#### Scenario: Log keeps everything
- **WHEN** the board hides older detail
- **THEN** the iteration log still holds every revision in full

### Requirement: Finished task aging
WHEN a task becomes done or cancelled, the iteration view SHALL keep it in the default list for 3 more iterations, then hide it.
WHILE a task is hidden, the All filter and its task detail SHALL still show it.

#### Scenario: Kept for three iterations
- **WHEN** a task finishes in iteration 10
- **THEN** iterations 11, 12, and 13 list it in the default list, and iteration 14 hides it

#### Scenario: Hidden task remains reachable
- **WHEN** a task is hidden and the captain selects All or opens the task
- **THEN** the board shows the task

### Requirement: Home coverage
The board SHALL show tasks from the main home and from every registered secondmate home.

#### Scenario: Secondmate task
- **WHEN** a registered secondmate home holds a task
- **THEN** the board lists the task with its home name

### Requirement: Jira keys as links
The board SHALL show a Jira key as a link only, with no Jira status read.

#### Scenario: Link only
- **WHEN** a task note names a Jira key
- **THEN** the board renders the key as a link and shows no Jira status

### Requirement: Fleet-integrity warnings
The board SHALL show fleet-integrity warnings in their own section, and never as queued work.

#### Scenario: Warning placement
- **WHEN** the snapshot reports a main-inventory gate or an unavailable secondmate home
- **THEN** the board shows it in the warnings section and excludes it from the queued count and the dispatch action
