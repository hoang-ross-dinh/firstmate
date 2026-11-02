## Context

The captain reviews fleet work through a chat Recap and the `/bearings lavish` board.
No script produces the chat Recap, because its format exists only in agent memory.
The board is stale because an agent composes its payload and nothing rebuilds it between `/bearings lavish` calls.
Backlog note edits replace text, so the backlog keeps no per-task history.

The board already routes answers to the captain-hold keyed-answer intake through a supervised runner (`bin/fm-procevent-lavish.sh` feeding `bin/fm-captain-hold.sh`).
Lavish watches the artifact file and reloads by itself, and keeps scroll, unsent annotation text, `data-lavish-question` answers, and queued feedback across reloads.
Lavish does not keep application-owned form text.

The captain grilled the design and confirmed 13 decisions (D1 to D13).
This document records each one so the reasons survive.
The grill sources are the request and the grill report in the Quarterdeck architect home (`data/quarterdeck-ticket-ui-griller/request.md` and `report.md`).

After the grill the captain dropped Beads.
All backlogs stay on the tasks-axi markdown backend.
The rule that the board reads backlogs only through tasks-axi verbs still applies.

## Goals / Non-Goals

**Goals:**
- One review surface that replaces the chat Recap and the `/bearings lavish` board.
- A per-task history of revisions across iterations, kept in an append-only log.
- Feedback from the board to the first mate: hold answers and comments.

**Non-Goals:**
- Owner-aware answer routing to secondmate homes.
- Jira status sync.
- A separate web server.
- A backup of the iteration log.

## Decisions

### D1. Scope
- **Decision:** What outcome should the work deliver?
- **Captain's choice:** A full ticket system. The Fleet Recap board replaces the chat Recap and the `/bearings lavish` board as the review surface for all fleet tasks.
- **Rejected recommendation:** A live board only, with no ticket concept. The captain overrode it.
- **Reason:** The captain's request names a ticket management system with a live feed. The review need is history and feedback per task, which a live board without tickets does not give.

### D2. System of record
- **Decision:** Where does task data live?
- **Captain's choice:** The existing backlogs stay the system of record, plus a per-item change history. Unchanged items keep their state. The board reads tasks only through `bin/fm-bearings-snapshot.sh --json` and `bin/fm-tasks-axi.sh`, and owns no task data.
- **Rejected recommendation:** None. The captain accepted the recommendation.
- **Reason:** The backlogs already hold task state. A second task store would drift from them. The Beads move was dropped, so the markdown backend and its tasks-axi verbs stay the only read path.

### D3. Iteration
- **Decision:** What is an iteration?
- **Captain's choice:** Each time the captain sees a Recap. The publish command records one iteration, and no timer or backlog change alone creates one.
- **Rejected recommendation:** A log at both levels, per Recap and per task. The captain's choice superseded it. The per-task level survives as revisions inside an iteration entry (D6).
- **Reason:** The captain reviews in rounds. A round is the natural unit to compare against.

### D4. Ticket unit
- **Decision:** What is one ticket?
- **Captain's choice:** One backlog task. A theme code is a grouping label stored in the revision.
- **Rejected recommendation:** The Recap theme as the ticket. The captain overrode it.
- **Reason:** A Recap theme is not a backlog item, so a theme ticket has no durable identity and no backlog state. A backlog task has an id, a state, and an owner home.

### D5. Chat Recap
- **Decision:** What happens to the chat Recap?
- **Captain's choice:** The UI replaces it. One publish command, next to `fm-bearings-board.sh build`, records the iteration. The chat gets a one-line pointer.
- **Rejected recommendation:** None. The captain accepted the recommendation.
- **Reason:** The Recap format exists only in agent memory. One command makes the publication deterministic and testable.

### D6. Revision content
- **Decision:** What does a revision hold?
- **Captain's choice:** The task's backlog fields (state, title, home, repo, hold reason, blockers, PR or MR URL, issue URL, note) plus the first mate's summary, emoji, theme code, and reply terms at publish time. A task with no field change gets no new revision.
- **Rejected recommendation:** None. The captain accepted the recommendation.
- **Reason:** Storing only changes keeps the log small. The history shows what changed and when.

### D7. Feedback routing
- **Decision:** How does the captain's feedback reach the first mate?
- **Captain's choice:** Hold answers go to the captain-hold keyed-answer intake. Comments go to `bin/fm-inbox.sh note` with a request id. Inbox replies render as the comment thread.
- **Rejected recommendation:** None. The captain accepted the recommendation.
- **Reason:** The captain-hold intake is the one place decisions are recorded, so no parallel decision store exists. A comment is not a decision, and the inbox is the existing capture surface. A request id makes a repeated delivery return the original note.

### D8. Hosting and page size
- **Decision:** Where does the board run, and how large may the page grow?
- **Captain's choice:** On the existing Lavish session, extended, with no new server and no new port. Comment boxes use the Lavish question markup so drafts survive reload. The page renders the last 30 iterations in full and older revisions as one line each. The records keep everything.
- **Rejected recommendation:** None. The captain accepted the recommendation.
- **Reason:** Lavish already serves the board and keeps question answers across reload. Estimated history growth is about 3 MB per month without a display window, so the window keeps the page small.

### D9. Home coverage
- **Decision:** Which homes does the board cover?
- **Captain's choice:** All homes. Answer buttons appear only where routing works. Otherwise the board shows "answer in chat". D14 later superseded the "answer in chat" part.
- **Rejected recommendation:** None. The captain accepted the recommendation.
- **Reason:** The board documentation names one gap: a secondmate hold's answer request is refused in the main home until owner-aware routing ships. That routing is out of scope.

### D10. Finished tasks
- **Decision:** How long does a finished task stay in the default list?
- **Captain's choice:** Keep it for 3 iterations (K=3), then hide it from the default list. The All filter and the task detail still show it.
- **Rejected recommendation:** Show a finished task once. The captain overrode it.
- **Reason:** A finished task visible for several rounds lets the captain confirm the outcome before it leaves the list. Three iterations is the captain's chosen number.

### D11. Jira
- **Decision:** How does the board treat Jira?
- **Captain's choice:** Link only. The board shows a Jira key as a link and the publish command makes no Jira call.
- **Rejected recommendation:** None. The captain accepted the recommendation.
- **Reason:** Jira status sync is out of scope. A link costs nothing and needs no credential.

### D12. One board
- **Decision:** How does the new board replace the old one?
- **Captain's choice:** One board directly. It replaces `/bearings lavish` at the stable board path and session. Merge and dispatch are task actions that reuse the existing `merge.<task-id>` and `dispatch.charted` routes.
- **Rejected recommendation:** A two-phase rollout with both boards. The captain chose the direct replacement.
- **Reason:** One board means one surface to review. The captain accepted the lack of a fallback board. Because of that risk, the existing `fm-bearings-board.sh build` path and its tests stay working until the new board meets its acceptance criteria.

### D13. Storage
- **Decision:** Where does the iteration log live?
- **Captain's choice:** An append-only file in the main home's gitignored `data/` directory. Only the main first mate's publish command writes it. No backup is in scope.
- **Rejected recommendation:** None. The captain accepted the recommendation.
- **Reason:** The log is private operational state. The captain accepted that history is lost if the disk is lost.

### D14. Answers on secondmate cards
- **Decision:** What does a waiting card show when its task lives in a secondmate home?
- **Captain's ask:** "I want the web to support a way to answer or feedback to the agent => the term "answer in chat" is not telling the main purpose of the action".
- **Options:** A, change the wording only. B, show answer buttons on every waiting card and relay a secondmate answer through the first mate. C, route the answer directly to the owning secondmate home.
- **Captain's choice:** B. Every waiting card shows its reply terms as answer buttons plus the comment box.
- **Rejected recommendation:** None recorded. A was rejected because it keeps the gap. C stays a possible later follow-up, because it needs owner-aware routing in the keyed-answer intake.
- **Reason:** The captain wants the board to carry every answer. The existing comment route already reaches the first mate with a request id, so B adds no decision store and writes into no secondmate home.

### D15. Priority order
- **Decision:** In what order does the board list items?
- **Captain's ask:** "I want it to order items with their Priority from High to Low".
- **Options:** None offered. The ask names the order.
- **Captain's choice:** Priority is the item's emoji: red is high, yellow is medium, green is low, and any other or empty emoji is last. Rows inside a theme group sort by priority first, then waiting-on-you first, then title. Theme groups sort by the best priority among their visible rows, then alphabetically with "misc" last.
- **Rejected recommendation:** None recorded.
- **Reason:** The captain reads the board top down, so the most urgent items must come first. The emoji already carries priority in the chat Recap, so no new field is needed.

### D16. Task detail as a slide-in panel
- **Decision:** How does the board show a task's detail?
- **Captain's ask:** "Can we make the details view as a slide in rather than a page switch, problem is - I need to scroll up to click "Back to Iteration X" - When I'm back on the Iteration view, it starts on the top of the page, I need to find the previous scroll location to scan the next item".
- **Captain's choices:** Panel shape: "Right side, wide (~70%)", with only a strip of the list visible and the full width on a narrow screen. Close: "Close button pinned on top, Esc key", with the close button visible while the panel scrolls and the list keeping its scroll position. Next and previous item inside the panel: "No, close and reopen".
- **Rejected recommendation:** None recorded.
- **Reason:** The list stays rendered behind the panel, so opening and closing never moves the list. The panel header holds the close button, so the captain never scrolls to find it. A reload starts with the panel closed, because the open task is not stored.

### D17. Live updates
- **Decision:** How does a new iteration reach a board that is already open?
- **Captain's ask:** "Can we make the page lively by pushing the iteration to the current page rather than opening a new page, it's like a spamming to me".
- **Captain's choices:** A publish opens a browser tab "Never automatically". When the open page receives a new iteration it should "Keep place, show a badge".
- **Choice:** Every `fm-bearings-board.sh build` call passes `--no-open` to `lavish-axi`, for the establish and the reopen call. Lavish reloads the artifact frame in full when the file changes, so the page saves its view in `sessionStorage` and restores it on load. A small "Iteration N arrived" badge shows while the reader views an older iteration than the newest.
- **Scope of no-open:** All `build` callers, not only the recap path. The recap path and the older `/bearings lavish` path share one establish function, and a tab per build is the same spam in both. The captain opens the board from its URL.
- **Liveness fix:** `lavish-axi` lists a live session that holds unread prompts as `feedback`. The build treats `open` and `feedback` as live, so it no longer reopens (and opens a tab for) a live board.
- **Reason:** The Lavish session, bind and listener stay unchanged. Only the browser launch and the page's own state change.

### D19. Blocked label
- **Decision:** How does the board show a task that waits on another task?
- **Captain's ask:** "Support the blocked label on this item on the Live board".
- **Choice:** A task whose current revision has blockers shows a "blocked" badge on its row and in its detail panel, beside the existing "blocked by <ids>" text. A task with no blockers shows no badge. The blocker ids come from the backlog `blocked_by` field that the collection reads through tasks-axi for every home, queued, held and in-flight tasks alike.
- **Rejected recommendation:** None recorded.
- **Reason:** The small "blocked by" line was easy to miss. A badge in the row's badge group gives the captain the same scan cue as the state and waiting badges. The change records no dependency and edits no backlog.

## Implementation approach

These choices serve the decisions above and are the implementer's, not the captain's.

- **Iteration log.** A JSON Lines file `data/recap-iterations.jsonl`. Each line is one iteration entry: sequence number, publish time, the ids of every task present, and the new revisions. The reader computes each task's last revision by scanning. A line without a closing newline or with invalid JSON is skipped and reported. Appending uses one write of a complete line, preceded by a newline when the file does not end in one.
- **Publish command.** `bin/fm-recap-publish.sh publish <recap.json>`. The first mate composes `<recap.json>` with its summary, emoji, theme code, and reply terms per task id. The command reads backlog fields through the bearings snapshot and tasks-axi verbs, appends the iteration, builds the board, and prints the chat-line facts. A `refresh` subcommand rebuilds the board from the existing log without appending an iteration, so rendering a reply never costs an iteration.
- **Board build.** `bin/fm-bearings-board.sh build` accepts a second payload schema, `fm-recap-board.v1`, and selects a new template for it. It reuses the existing session establishment, binding, arming, and reopening sequence. The `fm-bearings-board.v1` path and its tests stay unchanged. The publish command calls this build, so an ended session reopens through the existing sequence.
- **Display window.** The publish command embeds full revisions for the last 30 iterations and one line per older revision. The log keeps everything.
- **Answer route.** The template keeps the existing `fm-bearings-answer.v1` question markup for hold answers. A main-home card keeps that path. A secondmate-home card shows the same reply terms, and its answer travels the comment route (D14): the context carries `kind: "answer"`, and the inbox note body starts with `[recap task=<home>:<id> iteration=<n> answer] `.
- **Comment route.** Each task detail has a comment box that uses `data-lavish-question`. Its context carries a new schema, `fm-bearings-comment.v1`, which the existing answer parser ignores. The Lavish adapter gains a `comments` command. The generic runner feeds each comment to `fm-inbox.sh note --request-id <id>` with a tag naming the task id and iteration. The request id derives from the source id, the capture sequence, and the task id, so a repeated delivery replays the original note.
- **Reply thread.** The publish and refresh commands read `fm-inbox.sh receipts`, match notes by their task tag, and embed each comment with its reply in the payload. Threads are display data and do not enter revisions.
- **Task actions.** Merge and dispatch buttons reuse the question keys `merge.<task-id>` and `dispatch.charted`. The buttons appear only for main-home tasks, because the existing handlers resolve the PR and the backlog entry in the main home.

## Risks / Trade-offs

- [No fallback board after the direct replacement (D12)] -> Keep the existing build path and tests working, and replace the skill text only when the new board meets its acceptance criteria.
- [A comment box outside the Lavish question markup loses typed text on reload] -> Use `data-lavish-question` and add a test that the template renders it.
- [A comment could forge a decision key] -> The comment uses its own schema, and the existing answer parser ignores it. A test covers a comment that contains a task id.
- [The log has no backup] -> The captain accepted this. The design adds no backup.
- [A crash can leave an incomplete last line] -> The reader skips and reports it, and the next append starts on a new line.
- [Two publishes at once] -> The publish command takes a lock on the log directory before it reads the last sequence number.

## Open Questions

None blocking. The grill left the Jira choice open, and the captain later decided there is no Jira ticket.

### D18. Panel keyboard scrolling
- **Decision:** Which keys scroll the task detail panel?
- **Captain's ask:** "The Home/End button does not work in the Comment textbox, it works for scrolling the detail panel (I do not like that). Use the page up/down buttom for the details panel scrolling".
- **Options:** None offered. The ask names the keys.
- **Captain's choice:** PageUp and PageDown scroll the open panel, and only when focus is outside an editable field. Home, End and every other editing key keep their native behavior, and the board binds no scroll to Home or End.
- **Rejected recommendation:** None recorded.
- **Reason:** A text field needs Home and End to move the caret. The board keeps every key in a field away from any panel scroll binding.
