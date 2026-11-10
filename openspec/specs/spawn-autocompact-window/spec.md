# spawn-autocompact-window Specification

## Purpose
The `--autocompact-window` flag of `fm-spawn.sh` sets the Claude auto-compact window for one ship or scout launch.
A flag value takes precedence over the home's configured window and is carried to every relaunch of that task.

## Requirements
### Requirement: Flag sets the window
WHEN `fm-spawn.sh` receives `--autocompact-window <tokens>` for a claude ship or scout, it SHALL launch the worker with CLAUDE_CODE_AUTO_COMPACT_WINDOW set to that value.
Test: `tests/fm-spawn-dispatch-profile.test.sh` - test_autocompact_window_flag_overrides_config

#### Scenario: Space and equals forms
- **WHEN** a claude ship spawns with `--autocompact-window 700000` or `--autocompact-window=700000`
- **THEN** the worker launches with CLAUDE_CODE_AUTO_COMPACT_WINDOW=700000

### Requirement: Flag precedence over the config file
WHEN both the flag and `config/claude-crew-autocompact-window` give a value, `fm-spawn.sh` SHALL use the flag value.
Test: `tests/fm-spawn-dispatch-profile.test.sh` - test_autocompact_window_flag_overrides_config

#### Scenario: Flag wins
- **WHEN** the config file holds 350000 and the flag gives 700000
- **THEN** the worker launches with CLAUDE_CODE_AUTO_COMPACT_WINDOW=700000

### Requirement: Value range
IF the flag value is not an integer from 100000 to 1000000, THEN `fm-spawn.sh` SHALL refuse before any launch and name the flag.
Test: `tests/fm-spawn-dispatch-profile.test.sh` - test_autocompact_window_flag_overrides_config

#### Scenario: Value too small
- **WHEN** a claude ship spawns with `--autocompact-window=99999`
- **THEN** the spawn exits non-zero, names `--autocompact-window`, and launches nothing

### Requirement: Claude harness only
IF the flag is given with a harness other than claude, THEN `fm-spawn.sh` SHALL refuse the spawn before any launch.
Test: `tests/fm-spawn-dispatch-profile.test.sh` - test_autocompact_window_flag_refuses_non_claude_harness

#### Scenario: Other harness
- **WHEN** a ship resolves to a harness other than claude and the flag is given
- **THEN** the spawn exits non-zero with "--autocompact-window requires --harness claude"

### Requirement: No secondmate
IF the flag is given for a secondmate spawn, THEN `fm-spawn.sh` SHALL refuse the spawn.
Test: `tests/fm-spawn-dispatch-profile.test.sh` - test_autocompact_window_flag_overrides_config

#### Scenario: Secondmate spawn
- **WHEN** a secondmate spawns with `--autocompact-window 700000`
- **THEN** the spawn exits non-zero and launches nothing

### Requirement: Flag value is recorded
WHEN the flag sets the window, `fm-spawn.sh` SHALL record the value in the task metadata.
Test: `tests/fm-spawn-dispatch-profile.test.sh` - test_autocompact_window_flag_overrides_config

#### Scenario: Metadata line
- **WHEN** a claude ship spawns with `--autocompact-window 700000`
- **THEN** the task metadata holds `autocompact_window=700000`

### Requirement: Config value is not recorded
WHEN the window comes from the config file, `fm-spawn.sh` SHALL record no window value in the task metadata.
Test: `tests/fm-spawn-dispatch-profile.test.sh` - test_autocompact_window_flag_overrides_config; `tests/fm-spawn-compact-adviser-disable.test.sh` - test_relaunch_replays_the_autocompact_window_flag

#### Scenario: Config only
- **WHEN** the config file holds 350000 and no flag is given
- **THEN** the task metadata holds no `autocompact_window` line

### Requirement: Relaunch replays the recorded value
WHEN a task with a recorded window relaunches, `fm-spawn.sh` SHALL apply the recorded value over the config file value.
Test: `tests/fm-spawn-compact-adviser-disable.test.sh` - test_relaunch_replays_the_autocompact_window_flag

#### Scenario: Recorded and configured
- **WHEN** the metadata records 700000, the config file holds 350000, and the task relaunches
- **THEN** the worker relaunches with CLAUDE_CODE_AUTO_COMPACT_WINDOW=700000

### Requirement: Relaunch refuses the flag
IF a relaunch passes `--autocompact-window`, THEN `fm-spawn.sh` SHALL refuse the relaunch.
Test: `tests/fm-spawn-dispatch-profile.test.sh` - test_autocompact_window_flag_overrides_config

#### Scenario: Flag on relaunch
- **WHEN** `fm-spawn.sh --relaunch` runs with `--autocompact-window 700000`
- **THEN** the relaunch exits non-zero with "--autocompact-window cannot override"

### Requirement: Relaunch onto another harness
WHEN a task with a recorded window relaunches onto a harness other than claude, `fm-spawn.sh` SHALL drop the recorded window.
Test: none

#### Scenario: Harness change
- **WHEN** a task recorded with 700000 relaunches on another harness
- **THEN** the worker launches without CLAUDE_CODE_AUTO_COMPACT_WINDOW
