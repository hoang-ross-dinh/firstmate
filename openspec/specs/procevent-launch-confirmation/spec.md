# procevent-launch-confirmation Specification

## Purpose
The process-event reconcile confirms that each runner it launches takes its source's claim.
A slow but live runner is treated as uncertain for one cycle, so that a healthy launch is not reported as failed.

## Requirements
### Requirement: Confirmed launch
WHEN a launched runner takes the source's claim within the confirm window, the reconcile SHALL count the launch as started.
Test: `tests/fm-procevent.test.sh` - "a launch that cannot confirm is announced once per failure episode"

#### Scenario: Repaired source
- **WHEN** a runner takes its claim inside the confirm window
- **THEN** the reconcile reports `started=1` and `failed=0` and raises no launch-failed notification

### Requirement: Runner exits before its claim
IF a runner exits without a claim inside the confirm window, THEN the reconcile SHALL report a failed launch.
Test: `tests/fm-procevent.test.sh` - "a launch that cannot confirm is announced once per failure episode"

#### Scenario: Damaged registration
- **WHEN** the runner dies before it can take its claim
- **THEN** the reconcile reports `failed=1` and raises one launch-failed notification for the episode

### Requirement: Slow live runner is uncertain
WHILE a runner is alive but has no claim when the confirm window ends, the reconcile SHALL record the launch as uncertain, not failed.
Test: `tests/fm-procevent.test.sh` - "a runner that claims after the confirm window is not reported as a failed launch"

#### Scenario: Claim after the window
- **WHEN** a runner takes its claim after the confirm window ends
- **THEN** the reconcile reports `uncertain=1` and `failed=0` and raises no launch-failed notification

### Requirement: Still unclaimed a cycle later
IF the next cycle finds the same runner alive and unclaimed, THEN the reconcile SHALL report a failed launch and start no second runner.
Test: `tests/fm-procevent.test.sh` - "a runner still unclaimed a cycle later is a failed launch, with no duplicate runner"

#### Scenario: Stuck runner
- **WHEN** an uncertain runner is still alive and unclaimed at the next cycle
- **THEN** the reconcile reports `failed=1` and `started=0`, exits non-zero, and raises one launch-failed notification

### Requirement: Runner gone a cycle later
IF the next cycle finds the uncertain runner gone without a claim, THEN the reconcile SHALL report a failed launch and launch the source again.
Test: `tests/fm-procevent.test.sh` - "a runner that dies before its claim after the window is still a failed launch"

#### Scenario: Runner died late
- **WHEN** an uncertain runner exits without a claim before the next cycle
- **THEN** the next cycle reports a failed launch and `started=1`

### Requirement: Lost claim race
WHEN a launched runner finds the source already claimed by a live owner, the reconcile SHALL not report a failed launch.
Test: `tests/fm-procevent.test.sh` - "a launch that loses the claim to a live owner is not reported as a failure"

#### Scenario: Attached start won
- **WHEN** an attached start takes the source before the reconcile runner claims it
- **THEN** the reconcile reports `failed=0` and raises no launch-failed notification
