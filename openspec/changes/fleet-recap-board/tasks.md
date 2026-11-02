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

## 6. Answers on secondmate cards (D14)

- [x] 6.1 Show reply-term answer buttons and the owning-home line on secondmate waiting cards, and remove the "answer in chat" text
- [x] 6.2 Carry a secondmate answer through the comment route with `kind: "answer"` and an answer-tagged inbox note
- [x] 6.3 Show relayed answers and their replies in the task thread
- [x] 6.4 Add tests for both card kinds, the relayed note fields, and repeated delivery

## 7. Priority order (D15)

- [x] 7.1 Order rows by emoji priority and theme groups by their best row priority in every view that groups rows
- [x] 7.2 Add a test for the group order and the row order

## 8. Task detail slide-in panel (D16)

- [x] 8.1 Show the task detail in a right-side panel over the list, about 70% wide and full width on a narrow screen, with a pinned header and a close button
- [x] 8.2 Close with the close button or the Esc key, remove the "Back to iteration" link, and keep the list rendered and unscrolled
- [x] 8.3 Add render-harness tests for the open, close, Esc, header, back-link removal, and closed-on-load behaviors

## 9. Live updates (D17)

- [x] 9.1 Pass `--no-open` on every `lavish-axi` establish and reopen call in the board build, and treat a `feedback` listing as live
- [x] 9.2 Restore the iteration, filter, open task and scroll after a reload, and show the "Iteration N arrived" badge
- [x] 9.3 Add tests for no-open, the `feedback` listing, place restore, and the badge show, click and clear

