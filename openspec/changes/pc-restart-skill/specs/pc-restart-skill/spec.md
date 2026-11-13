## ADDED Requirements

### Requirement: Indexed agent-only skill
The skill SHALL live at `.agents/skills/pc-restart/SKILL.md` with `user-invocable: false` and `metadata.internal: true`.
The skill SHALL be listed in `agent-skill-trigger-index` and in `docs/documentation-audiences.json`.
Test: `bin/fm-doc-audience-check.sh` - fails when the skill file is missing from the inventory

#### Scenario: Skill is classified
- **WHEN** the audience check runs on a tree that tracks the skill file
- **THEN** the check reports no unclassified skill file

### Requirement: Readiness checklist before a restart
The skill SHALL give a numbered Part A checklist that answers whether the restart is safe.
The checklist SHALL require that every live worker has committed work and is at a clean stop.
The checklist SHALL state that a relaunch cannot resume a worker conversation.
The checklist SHALL require a saved report or notes file for each griller.
The checklist SHALL require a copy of volatile board data out of the scratch directory.
Test: none

#### Scenario: Worker with uncommitted work
- **WHEN** a live worker's copy holds uncommitted changes
- **THEN** Part A tells the first mate to steer the worker to commit and to report the restart as not yet safe

### Requirement: Recovery checklist after a restart
The skill SHALL give a numbered Part B checklist with one action per item.
The checklist SHALL run session start once, read the startup network report, and ask the captain to load the SSH key when a fetch fails for authentication.
The checklist SHALL restore the board data, reconcile process-event listeners, and steer each second mate to reconcile its own workers.
The checklist SHALL rebase worker copies onto the latest default branch before tests that launch a browser.
The checklist SHALL leave watcher arming to the Stop hook and SHALL decide on each cut-off griller.
Test: none

#### Scenario: Unloaded SSH key
- **WHEN** the network report shows a fetch failure with an SSH authentication error
- **THEN** Part B tells the first mate to ask the captain to run `ssh-add` and to rerun the network checks

### Requirement: Point to owners
The skill SHALL name the owning script or skill for each step that another document already defines, and SHALL NOT repeat that procedure.
The skill SHALL NOT hard-code the path of the recap data's durable home.
Test: none

#### Scenario: Dead worker
- **WHEN** a direct report's endpoint is dead after the restart
- **THEN** Part B points to `stuck-crewmate-recovery` and does not restate its procedure

### Requirement: Generic wording
The skill SHALL contain no host name, ticket key, company name, user name, or machine-specific path, because the repository is public.
Test: none

#### Scenario: Public fork
- **WHEN** a reader scans the skill for private identifiers
- **THEN** the scan finds none
