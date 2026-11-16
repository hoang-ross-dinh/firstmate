## MODIFIED Requirements

### Requirement: Readiness checklist before a restart
The skill SHALL give a numbered Part A checklist that answers whether the restart is safe.
The checklist SHALL require that every live worker has committed work and is at a clean stop.
The checklist SHALL state that a relaunch resumes a Claude worker's conversation only while its recorded transcript exists, and that every other worker restarts from its instructions on disk.
The checklist SHALL require a saved report or notes file for each griller.
The checklist SHALL require a copy of volatile board data out of the scratch directory.
Test: none

#### Scenario: Worker with uncommitted work
- **WHEN** a live worker's copy holds uncommitted changes
- **THEN** Part A tells the first mate to steer the worker to commit and to report the restart as not yet safe
