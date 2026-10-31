## 1. Iteration log and publish command

- [x] 1.1 Add the iteration log reader and appender with sequence numbers, incomplete-last-line handling, and a log lock
- [x] 1.2 Add revision computation that stores a revision only for tasks whose stored fields changed
- [x] 1.3 Read task fields only through the bearings snapshot and tasks-axi verbs
- [x] 1.4 Add `bin/fm-recap-publish.sh` with `publish` and `refresh`, the display window, and the chat-line facts
- [x] 1.5 Add tests for sequence numbers, change-only revisions, append-only behavior, the torn last line, and the gitignored location

## 2. Board template views

- [x] 2.1 Add the `fm-recap-board.v1` payload schema and validation to `bin/fm-bearings-board.sh build`, keeping the old payload path unchanged
- [x] 2.2 Add the Fleet Recap template with the iteration view, theme groups, change marks, filters, and iteration navigation
- [x] 2.3 Add the task detail with newest-first history, field diffs, note diffs, and one-line older revisions
- [x] 2.4 Add finished-task aging, all-home coverage, Jira key links, and the fleet-integrity warnings section
- [x] 2.5 Add render tests for each view requirement and a test that the old payload still builds

## 3. Comment route

- [x] 3.1 Add comment boxes to the template with the Lavish question markup and the `fm-bearings-comment.v1` context
- [x] 3.2 Add the `comments` command to `bin/fm-procevent-lavish.sh` and prove the answer parser ignores comment rows
- [x] 3.3 Feed comments from `bin/fm-procevent.sh` to `fm-inbox.sh note` with a task and iteration tag and a derived request id
- [x] 3.4 Embed comment threads with their replies in the board payload
- [x] 3.5 Add tests for note creation, duplicate delivery replay, a comment that contains a task id, and reply rendering

## 4. Merge and dispatch task actions

- [x] 4.1 Add the merge button for main-home tasks with a ready PR or MR, sending `merge.<task-id>`
- [x] 4.2 Add the dispatch button for queued main-home tasks, sending `dispatch.charted`
- [x] 4.3 Show "answer in chat" for holds whose task is absent from the main backlog
- [x] 4.4 Add tests for each action's visibility and key

## 5. Replace the old board and verify

- [x] 5.1 Update `.agents/skills/bearings/SKILL.md` and the relevant docs so `/bearings lavish` publishes through the new command and the chat carries one line
- [x] 5.2 Confirm no new port, no `0.0.0.0` or `::` bind, and no tunnel appear in the change
- [x] 5.3 Run `bin/fm-lint.sh`, `bin/fm-doc-audience-check.sh`, and the bearings and procevent tests, and report the results
