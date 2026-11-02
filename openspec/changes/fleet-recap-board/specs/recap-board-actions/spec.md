## ADDED Requirements

### Requirement: Hold answers route to captain-hold
WHEN the captain sends a reply-term answer on a main-home hold, the board runner SHALL deliver it to the `bin/fm-captain-hold.sh` keyed-answer intake.
The board SHALL write no decision anywhere except through the captain-hold intake.

#### Scenario: Reply-term answer
- **WHEN** the captain sends the reply term "merge" on a main-home hold
- **THEN** the runner delivers the keyed answer to `bin/fm-captain-hold.sh` and writes no other decision record

#### Scenario: No parallel store
- **WHEN** the captain sends a comment
- **THEN** the comment creates no decision record

### Requirement: Comments route to the inbox with a request id
WHEN the captain sends a comment on a task, the board runner SHALL create a `bin/fm-inbox.sh note` tagged with the task id and iteration number, with a request id.
IF the runner delivers the same comment twice, THEN `fm-inbox.sh` SHALL return the original note and create no second note.

#### Scenario: Comment becomes a note
- **WHEN** the captain sends a comment on task T in iteration 8
- **THEN** the runner creates one note tagged with task T and iteration 8, carrying a request id

#### Scenario: Duplicate delivery
- **WHEN** the runner delivers the same comment twice with the same request id
- **THEN** `fm-inbox.sh` reports a replay and the inbox holds one note

#### Scenario: Comment cannot forge a decision
- **WHEN** a comment text contains a task id or a reply term
- **THEN** the runner delivers nothing to the captain-hold intake for it

### Requirement: Replies render as a thread
WHEN the first mate replies to a comment note, the task history SHALL show the reply under that comment.

#### Scenario: Reply shown
- **WHEN** the first mate replies to the note created for a comment and then publishes
- **THEN** the task history shows the reply under that comment

#### Scenario: No reply yet
- **WHEN** a comment note has no reply
- **THEN** the task history shows the comment without a reply

### Requirement: Merge task action
WHERE a task has a ready PR or MR, the board SHALL offer a merge button that sends the existing `merge.<task-id>` order.

#### Scenario: Merge button shown
- **WHEN** a main-home task has a ready PR
- **THEN** the board offers a merge button that sends the `merge.<task-id>` order

#### Scenario: No ready PR
- **WHEN** a task has no ready PR or MR
- **THEN** the board offers no merge button

### Requirement: Dispatch task action
WHERE a task is queued, the board SHALL offer a dispatch button that sends the existing `dispatch.charted` route.

#### Scenario: Dispatch button shown
- **WHEN** a main-home task is queued and not a warning
- **THEN** the board offers a dispatch button that sends the `dispatch.charted` route with that task id

### Requirement: Answer buttons on every waiting card
WHILE a task waits on the captain, the board SHALL show each of its reply terms as an answer button and a comment box.

#### Scenario: Main-home card
- **WHEN** a main-home task waits on the captain
- **THEN** the board offers its reply terms as answer buttons and keeps the captain-hold intake path

#### Scenario: Secondmate-home card
- **WHEN** a secondmate-home task waits on the captain
- **THEN** the board offers its reply terms as answer buttons and the comment box
- **AND** the card names the owning home and says the answer goes there through the first mate

### Requirement: Secondmate answers reach the first mate
WHEN the captain sends an answer on a secondmate-home card, the board runner SHALL create one inbox note for the first mate that names the home, the task id, and the exact answer text.
The runner SHALL derive the note's request id from the source id, capture sequence, and row position.
The board SHALL create no decision record and SHALL write into no secondmate home.

#### Scenario: Answer relayed
- **WHEN** the captain sends the term "go" on a card for task "x" in home "pm"
- **THEN** the inbox holds one note whose body names task "pm:x" and the text "go"
- **AND** the keyed-answer intake receives nothing

#### Scenario: Repeated delivery
- **WHEN** the runner delivers the same capture twice
- **THEN** the inbox holds one note for that answer

### Requirement: No answer-in-chat wording
The board SHALL NOT tell the captain to answer in chat.

#### Scenario: Secondmate card text
- **WHEN** the board shows a secondmate-home card that waits on the captain
- **THEN** the card text does not contain "answer in chat"
