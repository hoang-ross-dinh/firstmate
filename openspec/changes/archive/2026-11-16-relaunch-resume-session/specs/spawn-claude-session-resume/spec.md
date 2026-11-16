## ADDED Requirements

### Requirement: Launch records a session id
WHEN `fm-spawn.sh` launches a claude ship or scout, it SHALL pass `--session-id <uuid>` and record the same id as `claude_session=` in the task record.
Test: `tests/fm-spawn-claude-session-resume.test.sh` - test_fresh_spawn_records_the_session

#### Scenario: Fresh spawn
- **WHEN** a claude ship spawns
- **THEN** the launch line carries `--session-id <uuid>` and the task record holds `claude_session=<uuid>` with the same value

### Requirement: Relaunch resumes the recorded conversation
WHEN a task whose previous harness was claude relaunches onto claude and the recorded id's transcript exists under the Claude config root the launch uses, `fm-spawn.sh --relaunch` SHALL pass `--resume <id>` and keep the recorded id.
Test: `tests/fm-spawn-claude-session-resume.test.sh` - test_relaunch_resumes_when_the_transcript_exists

#### Scenario: Surviving transcript
- **WHEN** the record holds `claude_session=<id>` and `<id>.jsonl` exists under the config root's `projects/`
- **THEN** the replacement launch carries `--resume <id>`, no `--session-id`, and no fallback notice

### Requirement: Fallback to a fresh conversation
IF the recorded id is absent, malformed, or has no transcript, THEN `fm-spawn.sh --relaunch` SHALL start a fresh conversation with a new `--session-id`, record the new id, and print one `notice:` line on stderr that the conversation could not be resumed.
Test: `tests/fm-spawn-claude-session-resume.test.sh` - test_relaunch_falls_back_when_the_transcript_is_gone, test_relaunch_falls_back_when_no_id_is_recorded

#### Scenario: Transcript gone
- **WHEN** the record holds an id whose transcript no longer exists
- **THEN** the replacement launch carries a different `--session-id`, the record holds that new id, and one notice line names the missing transcript

#### Scenario: Legacy record
- **WHEN** the record holds no `claude_session`
- **THEN** the relaunch starts fresh, records a new id, and prints a notice that no session id was recorded

### Requirement: Harness switch is not a failed resume
WHEN a task relaunches onto claude from another harness, `fm-spawn.sh --relaunch` SHALL start a fresh conversation, record its id, and print no resume notice.
Test: `tests/fm-spawn-claude-session-resume.test.sh` - test_other_harness_switch_is_silent

#### Scenario: Codex to claude
- **WHEN** a codex task relaunches with `--harness claude`
- **THEN** the launch carries `--session-id`, no `--resume`, and prints no "could not resume" line

### Requirement: Scope
The behavior SHALL apply only to claude ship and scout launches built from the launch template.
A secondmate, a raw launch command, and every other harness SHALL launch exactly as before and record no `claude_session`.
Test: none

#### Scenario: Other harness
- **WHEN** a codex ship spawns
- **THEN** its task record holds no `claude_session` line

### Requirement: Launch never fails for lack of an id generator
IF no UUID generator is available, THEN `fm-spawn.sh` SHALL launch without `--session-id` and record no id.
Test: none

#### Scenario: No generator
- **WHEN** `uuidgen` is not on the path
- **THEN** the spawn succeeds and the task record holds no `claude_session` line
