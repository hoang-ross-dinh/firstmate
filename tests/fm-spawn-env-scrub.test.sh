#!/usr/bin/env bash
# tests/fm-spawn-env-scrub.test.sh - a worker pane must not inherit stale session
# values from its backend daemon, and must still get every value the spawn sets
# for it on purpose.
#
# The assertions never read bin/fm-spawn.sh's source for behavior. They drive the
# real spawn against a fake pane, then EXECUTE the pane lines and launch command
# the pane received, in a synthetic pane environment that carries a leaked value
# for every scrubbed name, with the harness binary replaced by a probe that
# prints what it was started with. Every name and value here is synthetic.
set -u

# shellcheck source=tests/fixtures.sh
. "$(dirname "${BASH_SOURCE[0]}")/fixtures.sh"

# shellcheck source=bin/fm-trace-context-lib.sh
. "$ROOT/bin/fm-trace-context-lib.sh"

TMP_ROOT=$(fm_test_tmproot fm-spawn-env-scrub)

# The names the scrub must drop. This copy is the contract; bin/fm-spawn.sh keeps
# the list the pane actually receives, and the tests compare the two by behavior.
SCRUB_NAMES='FM_HOME FM_STATE_OVERRIDE FM_SPAWN_NO_GUARD FM_SESSION_START_STAGE_FILE
FM_BOOTSTRAP_NETWORK FM_BOOTSTRAP_NETWORK_LOCK_PID FM_BOOTSTRAP_PARALLEL_DIR
FM_TIMING_EPOCH_MS FM_TIMING_LOG
CLAUDE_CODE_BRIDGE_SESSION_ID CLAUDE_CODE_CHILD_SESSION CLAUDE_CODE_MESSAGING_SOCKET
CLAUDE_CODE_MESSAGING_TOKEN CLAUDE_CODE_SESSION_ID CLAUDE_CODE_SESSION_ATTENDED
CLAUDE_PID CLAUDE_ENV_FILE CLAUDE_PROJECT_DIR CLAUDECODE TRACEPARENT'

# Values the scrub must never let through, and never print.
leak_value() { printf 'synthetic-leak-%s' "$1"; }

make_case() {  # <name> <id>
  local case_dir="$TMP_ROOT/$1"
  CASE_DIR=$case_dir
  HOME_DIR="$case_dir/home"
  PROJ_DIR="$case_dir/project"
  WT_DIR="$case_dir/wt"
  LAUNCH_LOG="$case_dir/launch.log"
  PANE_LOG="$case_dir/pane.log"
  FAKEBIN_DIR=$(fm_test_make_spawn_fakebin "$case_dir/fake")
  fm_test_spawn_home "$HOME_DIR" codex
  fm_git_worktree "$PROJ_DIR" "$WT_DIR" "wt-$1"
  fm_test_spawn_brief "$HOME_DIR" "$2"
}

run_case_spawn() {
  : > "$LAUNCH_LOG"
  : > "$PANE_LOG"
  FM_FAKE_LAUNCH_LOG="$LAUNCH_LOG" FM_FAKE_PANE_LOG="$PANE_LOG" \
    fm_test_run_spawn "$HOME_DIR" "$WT_DIR" "$FAKEBIN_DIR" "$@"
}

# The probe prints "<name>=<value>" or "<name>=unset" for the names baked into it,
# so the assertion reads the environment a real agent would have started with.
# The names ride in the script rather than the environment because an allowlisted
# launch starts from a cleared one.
install_probe() {  # <fakebin> <names>
  cat > "$1/codex" <<SH
#!/bin/sh
for n in $2; do
  eval "v=\\\${\$n-__unset__}"
  if [ "\$v" = __unset__ ]; then printf '%s=unset\\n' "\$n"; else printf '%s=%s\\n' "\$n" "\$v"; fi
done
SH
  chmod +x "$1/codex"
}

# Replay the pane exactly as the real pane shell would: the `unset` and `export`
# lines in the order they were typed, then the launch command. The pane starts
# with a leaked value for every scrubbed name plus ordinary configuration.
replay_pane() {  # <extra-names-to-probe>
  local names n
  names=$(printf '%s ' $SCRUB_NAMES FM_QUARTERDECK $1)
  install_probe "$FAKEBIN_DIR" "$names"
  local -a pane_env=(HOME="$CASE_DIR/pane-home" PATH="$FAKEBIN_DIR:$PATH" TERM=xterm \
    TMUX=synthetic-pane FM_QUARTERDECK=synthetic-quarterdeck)
  for n in $SCRUB_NAMES; do
    pane_env+=("$n=$(leak_value "$n")")
  done
  env -i "${pane_env[@]}" \
    /bin/sh -c "$(grep -E '^(unset|export) ' "$PANE_LOG")
$(cat "$LAUNCH_LOG")"
}

probe_value() {  # <probe-output> <name>
  printf '%s\n' "$1" | sed -n "s/^$2=//p" | head -1
}

assert_no_leaked_value() {  # <label> <spawn-output>
  local n v
  for n in $SCRUB_NAMES; do
    v=$(leak_value "$n")
    if grep -qF -- "$v" "$PANE_LOG" "$LAUNCH_LOG" || printf '%s' "$2" | grep -qF -- "$v"; then
      fail "$1: a leaked value for $n was written into the pane, launch or spawn output"
    fi
  done
}

test_ship_pane_drops_leaked_names_and_keeps_intended_ones() {
  local out status seen n got unset_line goto
  make_case ship-open ship-open-a1
  out=$(run_case_spawn ship-open-a1 "$PROJ_DIR" --mode no-mistakes --yolo off)
  status=$?
  expect_code 0 "$status" "ship spawn should succeed: $out"
  seen=$(replay_pane "FM_TASK_ID COMPACT_ADVISER_DISABLE GOTMPDIR") \
    || fail "ship: the replayed pane failed to run"
  for n in $SCRUB_NAMES; do
    got=$(probe_value "$seen" "$n")
    assert_equals unset "$got" "ship: $n leaked from the pane into the worker"
  done
  assert_equals "ship-open-a1" "$(probe_value "$seen" FM_TASK_ID)" \
    "ship: the task id the spawn exports must reach the worker"
  assert_equals 1 "$(probe_value "$seen" COMPACT_ADVISER_DISABLE)" \
    "ship: the compact-adviser switch the spawn exports must reach the worker"
  assert_equals synthetic-quarterdeck "$(probe_value "$seen" FM_QUARTERDECK)" \
    "ship: captain configuration outside the scrub list must survive"
  assert_contains "$(probe_value "$seen" GOTMPDIR)" "/gotmp" \
    "ship: the scratch directory the spawn exports must reach the worker"
  assert_no_leaked_value "ship" "$out"
  # Order is the whole safety argument: a scrub typed after an export would undo it.
  unset_line=$(grep -n '^unset ' "$PANE_LOG" | head -1 | cut -d: -f1)
  goto=$(grep -n '^export GOTMPDIR=' "$PANE_LOG" | head -1 | cut -d: -f1)
  [ -n "$unset_line" ] && [ -n "$goto" ] || fail "ship: the pane log lacks the unset or the first export"
  [ "$unset_line" -lt "$goto" ] || fail "ship: the unset must precede every export"
  pass "ship pane drops leaked names and keeps the values the spawn sets"
}

test_scout_pane_drops_leaked_names() {
  local out status seen n got
  make_case scout-open scout-open-a1
  out=$(run_case_spawn scout-open-a1 "$PROJ_DIR" --scout)
  status=$?
  expect_code 0 "$status" "scout spawn should succeed: $out"
  seen=$(replay_pane "FM_TASK_ID") || fail "scout: the replayed pane failed to run"
  for n in $SCRUB_NAMES; do
    got=$(probe_value "$seen" "$n")
    assert_equals unset "$got" "scout: $n leaked from the pane into the worker"
  done
  assert_equals "scout-open-a1" "$(probe_value "$seen" FM_TASK_ID)" \
    "scout: the task id the spawn exports must reach the worker"
  pass "scout pane drops leaked names"
}

test_trace_carrier_is_set_after_the_scrub() {
  local out status seen tp
  make_case ship-trace ship-trace-a1
  : > "$HOME_DIR/config/trace-context"
  # The carrier is minted only inside a live session that froze the decision, so
  # give the case home that session record.
  printf '%s\n' "$$" > "$HOME_DIR/state/.lock"
  ( unset FM_TRACE_CONTEXT
    fm_trace_context_session_start "$HOME_DIR/config" "$HOME_DIR/state/.trace-context-effective" )
  out=$(run_case_spawn ship-trace-a1 "$PROJ_DIR" --mode no-mistakes --yolo off)
  status=$?
  expect_code 0 "$status" "trace-enabled ship spawn should succeed: $out"
  tp=$(sed -n 's/^export TRACEPARENT=//p' "$PANE_LOG" | head -1)
  [ -n "$tp" ] || fail "trace: an enabled home should export a trace carrier into the pane"
  seen=$(replay_pane "") || fail "trace: the replayed pane failed to run"
  assert_equals "$tp" "$(probe_value "$seen" TRACEPARENT)" \
    "trace: the worker must see the carrier the spawn exported, not the leaked one"
  pass "the trace carrier the spawn exports survives the scrub of the stale one"
}

test_secondmate_gets_its_own_home_not_the_leaked_one() {
  local sm out status seen want
  make_case secondmate-open sm-open
  sm="$CASE_DIR/secondmate-home"
  mkdir -p "$sm/bin" "$sm/data"
  printf '# Firstmate\n' > "$sm/AGENTS.md"
  printf '%s\n' sm-open > "$sm/.fm-secondmate-home"
  printf 'charter for sm-open\n' > "$sm/data/charter.md"
  printf '%s\n' 'projects/' 'state/' 'data/' 'config/' '.no-mistakes/' > "$sm/.gitignore"
  git -C "$sm" init -q -b main
  out=$(run_case_spawn sm-open "$sm" --secondmate)
  status=$?
  expect_code 0 "$status" "secondmate spawn should succeed: $out"
  seen=$(replay_pane "FM_ROOT_OVERRIDE") || fail "secondmate: the replayed pane failed to run"
  want=$(cd "$sm" && pwd -P)
  assert_equals "$want" "$(cd "$(probe_value "$seen" FM_HOME)" && pwd -P)" \
    "secondmate: FM_HOME must be the secondmate's own home, set after the scrub"
  assert_equals unset "$(probe_value "$seen" CLAUDE_CODE_SESSION_ID)" \
    "secondmate: another session's id leaked into the secondmate"
  assert_equals unset "$(probe_value "$seen" CLAUDE_CODE_MESSAGING_TOKEN)" \
    "secondmate: a messaging token leaked into the secondmate"
  assert_no_leaked_value "secondmate" "$out"
  pass "a secondmate gets its own FM_HOME while stale session values are dropped"
}

# A name the captain forwards on purpose is the captain's explicit choice and the
# scrub must not undo it, while every other leaked name is still cleared.
test_allowlisted_name_is_not_scrubbed() {
  local out status seen
  make_case ship-allow ship-allow-a1
  printf '%s\n' '# captain choice' CLAUDE_PROJECT_DIR > "$HOME_DIR/config/launch-env-allowlist"
  out=$(run_case_spawn ship-allow-a1 "$PROJ_DIR" --mode no-mistakes --yolo off)
  status=$?
  expect_code 0 "$status" "allowlisted ship spawn should succeed: $out"
  grep -E '^unset ' "$PANE_LOG" | grep -qw CLAUDE_PROJECT_DIR \
    && fail "allowlist: the unset line must leave a forwarded name alone"
  seen=$(replay_pane "") || fail "allowlist: the replayed pane failed to run"
  assert_equals "$(leak_value CLAUDE_PROJECT_DIR)" "$(probe_value "$seen" CLAUDE_PROJECT_DIR)" \
    "allowlist: a name the captain forwards must still reach the worker"
  assert_equals unset "$(probe_value "$seen" CLAUDE_CODE_SESSION_ID)" \
    "allowlist: a name the captain did not forward must stay dropped"
  pass "an allowlisted name keeps its value and the rest stay scrubbed"
}

# `unset` takes no pattern, so the list names every FM_BOOTSTRAP_* and FM_TIMING_*
# variable. A new name added under bin/ without joining the list would leak, so
# this fails the moment the two drift.
test_every_bootstrap_and_timing_name_is_listed() {
  local out status name missing=
  make_case ship-drift ship-drift-a1
  out=$(run_case_spawn ship-drift-a1 "$PROJ_DIR" --mode no-mistakes --yolo off)
  status=$?
  expect_code 0 "$status" "drift-check spawn should succeed: $out"
  for name in $(grep -rhoE '\b(FM_BOOTSTRAP|FM_TIMING)_[A-Z_]+' "$ROOT/bin" | sort -u); do
    grep -E '^unset ' "$PANE_LOG" | grep -qw "$name" || missing="$missing $name"
  done
  [ -z "$missing" ] || fail "names under bin/ missing from the scrub list:$missing"
  pass "every FM_BOOTSTRAP_* and FM_TIMING_* name under bin/ is in the scrub list"
}

test_ship_pane_drops_leaked_names_and_keeps_intended_ones
test_scout_pane_drops_leaked_names
test_trace_carrier_is_set_after_the_scrub
test_secondmate_gets_its_own_home_not_the_leaked_one
test_allowlisted_name_is_not_scrubbed
test_every_bootstrap_and_timing_name_is_listed
