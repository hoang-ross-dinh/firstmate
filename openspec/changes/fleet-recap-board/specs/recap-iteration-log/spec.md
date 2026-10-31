## ADDED Requirements

### Requirement: Publish records one iteration
WHEN the first mate publishes a Recap, the publish command SHALL append exactly one iteration entry with a sequence number one higher than the last.
An iteration SHALL NOT be created by a timer or by a backlog change alone.

#### Scenario: First publish
- **WHEN** the iteration log does not exist and the first mate publishes a Recap
- **THEN** the publish command creates the log with one entry whose sequence number is 1

#### Scenario: Later publish
- **WHEN** the last entry has sequence number 7 and the first mate publishes a Recap
- **THEN** the publish command appends one entry with sequence number 8

#### Scenario: Backlog change without publish
- **WHEN** a backlog task changes and no publish runs
- **THEN** the iteration log gains no entry

### Requirement: Revisions store changes only
WHEN the first mate publishes a Recap, the publish command SHALL store a new revision only for each task whose stored fields differ from its last revision.
WHEN a task has no change since its last revision, the board SHALL show that last revision with the iteration number it came from.

#### Scenario: One task changed
- **WHEN** a publish runs and exactly one of ten tasks has a changed stored field
- **THEN** the new entry holds one new revision and names the other nine tasks as unchanged

#### Scenario: Unchanged task display
- **WHEN** a task last changed in iteration 5 and the board shows iteration 8
- **THEN** the board shows the iteration 5 revision marked "unchanged since iteration 5"

#### Scenario: No field change
- **WHEN** a publish runs and no stored field of a task differs from its last revision
- **THEN** the publish command stores no revision for that task

### Requirement: Revision content
Each revision SHALL store the task's backlog state, title, home, repo, hold reason, blockers, PR or MR URL, issue URL, and note.
Each revision SHALL store the first mate's summary line, status emoji, theme code, and reply terms for that task.
A theme code SHALL be a grouping label stored in the revision, and one ticket SHALL equal one backlog task.

#### Scenario: Revision fields
- **WHEN** the publish command stores a revision
- **THEN** the revision carries every backlog field and every first mate field named above

#### Scenario: Summary change alone
- **WHEN** only the first mate's summary line of a task differs from its last revision
- **THEN** the publish command stores a new revision for that task

### Requirement: Append-only log
The iteration log SHALL be append-only, and no command SHALL rewrite or delete an earlier entry.

#### Scenario: Earlier entries stay intact
- **WHEN** the publish command appends an entry
- **THEN** every earlier line of the log is byte-identical to its state before the publish

### Requirement: Incomplete last line
IF the last line of the iteration log is incomplete, THEN the reader SHALL skip that line and report it.

#### Scenario: Torn last line
- **WHEN** the last line of the log lacks a closing newline or is not valid JSON
- **THEN** the reader returns every earlier entry and reports the skipped line

#### Scenario: Publish after a torn line
- **WHEN** a publish finds an incomplete last line
- **THEN** the publish command reports it and appends its entry on a new line, and never rewrites the incomplete line

### Requirement: Log location and writer
The iteration log SHALL live in the main home's gitignored `data/` directory.
Only the main first mate's publish command SHALL write it.

#### Scenario: Gitignored location
- **WHEN** a publish completes
- **THEN** the log file is under the main home's `data/` directory and `git status` reports no change for it

### Requirement: Backlog read path and Jira
The publish command SHALL read tasks only through `bin/fm-bearings-snapshot.sh --json` and `bin/fm-tasks-axi.sh`, and SHALL NOT read a backlog file directly.
The board SHALL own no task data.
The publish command SHALL make no Jira call.

#### Scenario: Read path
- **WHEN** the publish command collects tasks
- **THEN** every task field comes from a tasks-axi verb or the bearings snapshot

#### Scenario: Jira key
- **WHEN** a task note contains a Jira key
- **THEN** the publish command stores the key as text and makes no Jira request

### Requirement: Publish chat line
WHEN a publish completes, the first mate SHALL send one chat line with the iteration number, the changed theme codes, the count waiting on the captain, and the board URL.
The chat SHALL carry only that one-line pointer to the iteration.

#### Scenario: Chat line content
- **WHEN** iteration 8 publishes with changes in themes LW and QD and 2 tasks waiting on the captain
- **THEN** the chat line names iteration 8, themes LW and QD, the count 2, and the board URL
