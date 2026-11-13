## Why

A PC restart closed every worker terminal window, cleared the scratch directory that held the recap board data, and left worker copies that lacked a fix already on main.
No written checklist told the first mate what to check before the restart or what to repair after it.

## What Changes

- Add the agent-only skill `pc-restart` at `.agents/skills/pc-restart/SKILL.md`.
- Part A answers "can I restart now?": every live worker has committed work and is at a clean stop, a relaunch cannot resume a worker conversation, each griller has a saved report or notes file, and volatile board data is copied out of the scratch directory.
- Part B lists the recovery steps in order: run session start once, read the network report for an unloaded SSH key, restore the board data, reconcile process-event listeners, reconcile each worker and second mate, rebase worker copies before browser tests, leave watcher arming to the Stop hook, and decide on cut-off grillers.
- The skill points to the owning scripts and skills and does not repeat them.
- List the skill in `agent-skill-trigger-index` and in the documentation audience inventory.

Out of scope: any change to `AGENTS.md`, any script, and the recap data's durable home, which another change adds.

## Capabilities

### New Capabilities

- `pc-restart-skill`: the before-restart readiness checklist and after-restart recovery checklist as an agent-only skill.

### Modified Capabilities

None.

## Impact

- New file `.agents/skills/pc-restart/SKILL.md`, reached through the existing `.claude/skills` symlink.
- One line added to `.agents/skills/agent-skill-trigger-index/SKILL.md`.
- One entry added to `docs/documentation-audiences.json`.
