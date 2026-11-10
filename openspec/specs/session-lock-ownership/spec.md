# session-lock-ownership Specification

## Purpose
The firstmate session lock is taken only for a home that the running code root owns.
A session that runs from another home's code, or a task worker, cannot take or reclaim a firstmate home's lock.

## Requirements
### Requirement: Foreign home refusal
IF the home or its state directory belongs to a firstmate code root other than the running one, THEN `fm-lock.sh` SHALL refuse the lock.
Test: `tests/fm-session-lock-ancestry.test.sh` - test_inherited_foreign_home_is_never_locked

#### Scenario: Inherited home variable
- **WHEN** a worktree's `fm-lock.sh` runs with FM_HOME set to another firstmate home
- **THEN** the command exits non-zero and the message names the other home

#### Scenario: Inherited state variable
- **WHEN** a worktree's `fm-lock.sh` runs with FM_STATE_OVERRIDE set to another home's state directory
- **THEN** the command exits non-zero

### Requirement: Refusal writes nothing
WHEN `fm-lock.sh` refuses a foreign home, it SHALL write no lock file and no lock sidecar in that home.
Test: `tests/fm-session-lock-ancestry.test.sh` - test_inherited_foreign_home_is_never_locked

#### Scenario: No files
- **WHEN** the lock of a foreign home is refused
- **THEN** that home's `state/.lock` and `state/.lock-session` do not exist

### Requirement: Read-only instruction
WHEN `fm-lock.sh` refuses the lock for a foreign home, the refusal message SHALL tell the session to operate read-only.
Test: none

#### Scenario: Refusal text
- **WHEN** the lock of a foreign home is refused
- **THEN** the error message ends with "operate read-only until resolved"

### Requirement: Task worker refusal
IF a task worker requests the session lock of a firstmate home, THEN `fm-lock.sh` SHALL refuse the lock.
Test: `tests/fm-session-lock-ancestry.test.sh` - test_task_worker_never_locks_a_firstmate_home

#### Scenario: Worker on a firstmate home
- **WHEN** `fm-lock.sh` runs with FM_TASK_ID set and the home is a firstmate code root
- **THEN** the command exits non-zero and takes no lock

### Requirement: Task worker on a temporary home
WHEN a task worker requests the lock of a temporary home that is not a firstmate code root, `fm-lock.sh` SHALL take the lock.
Test: `tests/fm-session-lock-ancestry.test.sh` - test_task_worker_never_locks_a_firstmate_home

#### Scenario: Temporary home
- **WHEN** `fm-lock.sh` runs with FM_TASK_ID set and the home is a temporary directory
- **THEN** the command takes the lock

### Requirement: Own home still locks
WHEN a primary or secondmate home runs its own code, `fm-lock.sh` SHALL take that home's session lock.
Test: `tests/fm-session-lock-ancestry.test.sh` - test_a_home_running_its_own_code_still_locks

#### Scenario: Primary home
- **WHEN** a primary home runs its own `fm-lock.sh`
- **THEN** the command takes the lock

### Requirement: Stop hook never reclaims a foreign lock
WHEN a Stop hook runs in a marked worker slot, the hook SHALL never reclaim another home's session lock.
Test: `tests/fm-session-lock-ancestry.test.sh` - test_stop_hook_in_a_marked_slot_never_reclaims_a_foreign_lock

#### Scenario: Worker slot hook
- **WHEN** a Stop hook fires in a marked worker slot whose environment names another home
- **THEN** the other home's lock is unchanged

### Requirement: Marked worktree is primary only for its own state
The session-start nudge SHALL treat a marked linked worktree as a primary only when its state directory is its own `state/`.
Test: `tests/fm-sessionstart-nudge.test.sh` - test_marked_worktree_with_foreign_home_is_silent

#### Scenario: Foreign state
- **WHEN** a marked linked worktree runs with another home's state directory
- **THEN** the nudge treats the worktree as not a primary and stays silent
