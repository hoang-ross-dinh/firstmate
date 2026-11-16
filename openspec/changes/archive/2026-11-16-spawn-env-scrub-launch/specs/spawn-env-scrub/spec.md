## ADDED Requirements

### Requirement: Stale names are dropped from the pane
WHEN `fm-spawn.sh` launches a ship, scout, or secondmate into a pane, it SHALL type one `unset` of the scrub name list into that pane before any export and before the launch command.
The list SHALL contain `FM_HOME`, `FM_STATE_OVERRIDE`, `FM_SPAWN_NO_GUARD`, `FM_SESSION_START_STAGE_FILE`, every `FM_BOOTSTRAP_*` and `FM_TIMING_*` name used under `bin/`, `CLAUDE_CODE_BRIDGE_SESSION_ID`, `CLAUDE_CODE_CHILD_SESSION`, `CLAUDE_CODE_MESSAGING_SOCKET`, `CLAUDE_CODE_MESSAGING_TOKEN`, `CLAUDE_CODE_SESSION_ID`, `CLAUDE_CODE_SESSION_ATTENDED`, `CLAUDE_PID`, `CLAUDE_ENV_FILE`, `CLAUDE_PROJECT_DIR`, `CLAUDECODE`, and `TRACEPARENT`.
Test: `tests/fm-spawn-env-scrub.test.sh` - test_ship_pane_drops_leaked_names_and_keeps_intended_ones; test_scout_pane_drops_leaked_names

#### Scenario: Leaked session values
- **WHEN** the pane starts with a value for each listed name and a ship spawns
- **THEN** the worker starts with none of those names set

### Requirement: Intended values survive the scrub
The `unset` line SHALL precede every export the spawn sends.
WHEN the spawn sets a value for the worker, the worker SHALL receive that value and not the stale one.
The scrub SHALL NOT unset `PATH`, `HOME`, `FM_QUARTERDECK`, `FM_TASK_ID`, `FM_TASK_INBOX`, `GOTMPDIR`, or `COMPACT_ADVISER_DISABLE`.
Test: `tests/fm-spawn-env-scrub.test.sh` - test_ship_pane_drops_leaked_names_and_keeps_intended_ones; test_trace_carrier_is_set_after_the_scrub; test_secondmate_gets_its_own_home_not_the_leaked_one

#### Scenario: Trace carrier and secondmate home
- **WHEN** a trace-enabled ship spawns, or a secondmate spawns, into a pane that holds a stale `TRACEPARENT` or `FM_HOME`
- **THEN** the worker sees the carrier or the secondmate home the spawn set, not the stale value

### Requirement: Allowlisted names stay
IF `config/launch-env-allowlist` lists a scrub name, THEN the `unset` line SHALL omit that name.
Test: `tests/fm-spawn-env-scrub.test.sh` - test_allowlisted_name_is_not_scrubbed

#### Scenario: Forwarded name
- **WHEN** the allowlist lists `CLAUDE_PROJECT_DIR` and the pane holds a value for it
- **THEN** the worker receives that value and the other listed names stay dropped

### Requirement: Values are never written
The spawn SHALL handle scrub names only and SHALL NOT write a value of a scrubbed name into the pane, the launch command, or its output.
Test: `tests/fm-spawn-env-scrub.test.sh` - test_ship_pane_drops_leaked_names_and_keeps_intended_ones; test_secondmate_gets_its_own_home_not_the_leaked_one

#### Scenario: Leaked value stays out of logs
- **WHEN** a spawn runs in a pane that holds a leaked value for a listed name
- **THEN** the pane log, the launch log, and the spawn output do not contain that value

### Requirement: Name families stay complete
IF a `FM_BOOTSTRAP_*` or `FM_TIMING_*` name appears under `bin/` and is not in the scrub list, THEN `tests/fm-spawn-env-scrub.test.sh` SHALL fail.
Test: `tests/fm-spawn-env-scrub.test.sh` - test_every_bootstrap_and_timing_name_is_listed

#### Scenario: New bootstrap name
- **WHEN** a script under `bin/` starts reading a new `FM_BOOTSTRAP_` name that is not in the list
- **THEN** the drift test fails and names it
