---
name: pc-restart
description: Load before a planned PC restart to decide whether restarting is safe, and after any restart, planned or not, that closed worker windows or session processes.
user-invocable: false
metadata:
  internal: true
---

# PC restart

A restart closes every worker terminal window and session process, and it can clear the host's scratch directories.
Durable records in the home and commits on branches survive.
Conversations, uncommitted edits, and anything kept only in a scratch directory do not.
A relaunch cannot resume a worker conversation.
`bin/fm-control.sh <id> relaunch` starts a new agent from the instructions on disk plus a progress note ([transactional relaunch](../../../docs/agent-control.md#transactional-relaunch)).

## Part A - before the restart: can I restart now?

Restart only when every item passes.
When an item fails, fix it or tell the captain which worker or file blocks the restart.

1. Read each live worker's current state with `bin/fm-crew-state.sh <id>`.
2. Wait for each worker that is still working, or steer it with `bin/fm-send.sh` to reach a clean stop.
3. Check that each worker's local copy has no uncommitted changes.
   Use a read-only `git status` on the copy that `state/<id>.meta` records.
4. Steer a worker with uncommitted changes to commit them.
   Never commit for it and never force a teardown.
5. Steer each second mate to apply items 1 to 4 to its own workers.
   The main home does not supervise a second mate's child tree.
6. For each griller, confirm its report or notes file is saved in durable storage.
   Steer it to save one if it is not.
7. Publish pending recap edits, because the iteration log restores only what was published.
   Then confirm the recap file that `bin/fm-recap-publish.sh recap-path` prints is not in a scratch directory.
   Move any copy that is.
8. Tell the captain that the restart is safe, or name the first failing item.

## Part B - after the restart

1. Run `bin/fm-session-start.sh` once ([`AGENTS.md`](../../../AGENTS.md) section 3).
   Do not run its components separately.
2. Read the finished network report with `bin/fm-startup-network.sh report`.
3. When a fetch failure shows an SSH authentication error, the SSH key is probably not loaded.
   Ask the captain to run `ssh-add`, then rerun the network checks.
   Load `bootstrap-diagnostics` for the printed line.
4. Check the recap file that `bin/fm-recap-publish.sh recap-path` prints.
   When it is missing, run `bin/fm-recap-publish.sh restore` to rebuild it from the iteration log.
   The log cannot give back answers, entries for keys that were never backlog tasks, or the split between explicit links and derived chips, so re-add them.
5. Run `bin/fm-procevent.sh list` to reconcile process-event listeners.
   Run `bin/fm-procevent.sh reconcile` for any source that is not live.
   Load `process-event-sources` for a failed or orphaned source.
6. Read the current state of every direct report with `bin/fm-crew-state.sh <id>`.
   Load `stuck-crewmate-recovery` for each dead ordinary worker.
   Relaunch it only from its committed branch.
7. Steer each second mate to reconcile its own workers: retire dead records and respawn from committed branches.
   Load `secondmate-provisioning` for a dead second mate.
8. Before any worker runs tests that launch Chrome, steer it to rebase its copy onto the latest default branch.
   A stale copy lacks fixes that landed after it was made.
9. Follow the emitted supervision block for watcher arming.
   Where the harness has a turn-end Stop hook, let it arm the watcher ([turn-end guard](../../../docs/turnend-guard.md)).
   Do not arm a second supervision cycle by hand.
10. Decide for each griller cut off mid-interview.
    When its saved notes leave questions open, relaunch it with a note that points to them.
    Otherwise close it through ordinary cleanup.
