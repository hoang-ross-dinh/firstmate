#!/usr/bin/env bash
# Behavior tests for bin/fm-board-publish-guard.sh, the Stop hook that reminds
# the main home to publish the Fleet Recap board. Every home is a temporary
# git repo with synthetic status lines, a synthetic iteration log, and a fake
# clock (FM_BOARD_PUBLISH_NOW), so no test reads or writes a real home.
set -u

# shellcheck source=tests/lib.sh
# shellcheck disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

GUARD="$ROOT/bin/fm-board-publish-guard.sh"
TMP_ROOT=$(fm_test_tmproot fm-board-publish-guard)

command -v jq >/dev/null 2>&1 || { echo "skip: jq not found"; exit 0; }

# 2026-01-01T00:00:00Z, the synthetic publish time every home starts from.
P=1767225600
P_ISO=2026-01-01T00:00:00Z

# A main-home-shaped repo: plain checkout, AGENTS.md, bin/, state/, one
# publish at P, and one registered second mate "alpha". Callers capture it with
# $(...), so the name comes from mktemp rather than a counter the subshell loses.
make_home() {
  local home
  home=$(mktemp -d "$TMP_ROOT/home.XXXXXX")
  fm_git_init_commit "$home" >/dev/null
  mkdir -p "$home/bin" "$home/state" "$home/data" "$home/config"
  : > "$home/AGENTS.md"
  publish_at "$home" "$P_ISO" 1
  printf '%s\n' "- alpha - synthetic second mate (home: $TMP_ROOT/alpha-home; scope: tests; projects: none; added 2026-01-01)" \
    > "$home/data/secondmates.md"
  printf '%s\n' "$home"
}

publish_at() {  # <home> <iso> <seq>
  printf '{"schema":"fm-recap-iteration.v1","seq":%s,"at":"%s","tasks":[],"changed_themes":[]}\n' "$3" "$2" \
    >> "$1/data/recap-iterations.jsonl"
}

status_line() {  # <home> <id> <line>
  printf '%s\n' "$3" >> "$1/state/$2.status"
}

out='' err='' status=0
# run_guard <root> <now> [args...]: run the hook with <root> as the home.
run_guard() {
  local root=$1 now=$2
  shift 2
  out=$(printf '{"session_id":"synthetic","stop_hook_active":false}' \
    | FM_ROOT_OVERRIDE="$root" FM_HOME="$root" FM_BOARD_PUBLISH_NOW="$now" \
      bash "$GUARD" "$@" 2>"$TMP_ROOT/err")
  status=$?
  err=$(cat "$TMP_ROOT/err")
}

expect_silent_pass() {  # <label>
  expect_code 0 "$status" "$1"
  assert_equals '' "$out$err" "$1 prints nothing"
}

test_an_event_older_than_the_window_blocks() {
  local home
  home=$(make_home)
  status_line "$home" alpha "needs-decision [key=pick] [at=$((P + 60))]: choose one of two synthetic options"
  run_guard "$home" $((P + 60 + 31))
  expect_code 2 "$status" "an event 31s old"
  assert_contains "$err" "Fleet Recap board is stale: 1 captain-facing second-mate event(s)" "the block names the count"
  assert_contains "$err" "the oldest from alpha 31s ago" "the block names the second mate and the age"
  assert_contains "$err" "bin/fm-board-publish-guard.sh ack" "the block names the ack command"
  assert_equals '' "$out" "the block writes nothing on stdout"
  pass "an event older than the window after the last publish blocks"
}

test_an_event_inside_the_window_passes_silently() {
  local home
  home=$(make_home)
  status_line "$home" alpha "done [at=$((P + 60))]: synthetic work finished"
  run_guard "$home" $((P + 60 + 29))
  expect_silent_pass "an event 29s old"
  pass "an event inside the window passes silently"
}

test_the_oldest_event_sets_the_debounce() {
  local home
  home=$(make_home)
  status_line "$home" alpha "done [at=$((P + 10))]: first synthetic outcome"
  status_line "$home" alpha "blocked [at=$((P + 40))]: second synthetic outcome"
  run_guard "$home" $((P + 50))
  expect_code 2 "$status" "the oldest event is 40s old even though the newest is 10s old"
  assert_contains "$err" "2 captain-facing" "both events are counted"
  pass "the oldest unpublished event sets the debounce"
}

test_a_publish_clears_the_block() {
  local home
  home=$(make_home)
  status_line "$home" alpha "needs-decision [at=$((P + 60))]: synthetic decision"
  publish_at "$home" 2026-01-01T00:02:00Z 2
  run_guard "$home" $((P + 1000))
  expect_silent_pass "an event before the latest publish"
  pass "a publish clears it"
}

test_a_torn_last_publish_line_falls_back_to_the_previous_one() {
  local home
  home=$(make_home)
  status_line "$home" alpha "needs-decision [at=$((P + 60))]: synthetic decision"
  printf '{"schema":"fm-recap-iteration.v1","seq":2,"at":"2026-01-01T00:05:00Z","tas' >> "$home/data/recap-iterations.jsonl"
  run_guard "$home" $((P + 1000))
  expect_code 2 "$status" "a torn line is not a publish"
  pass "a torn last publish line does not count as a publish"
}

test_an_ack_clears_it_and_it_never_blocks_twice() {
  local home
  home=$(make_home)
  status_line "$home" alpha "needs-decision [at=$((P + 60))]: synthetic decision"
  run_guard "$home" $((P + 400))
  expect_code 2 "$status" "first stop blocks"
  run_guard "$home" $((P + 401))
  expect_silent_pass "a second stop for the same events"
  run_guard "$home" $((P + 402)) ack
  expect_code 0 "$status" "ack"
  assert_contains "$out" "acknowledged board events through 2026-01-01T00:06:42Z" "ack names its time"
  assert_equals "$((P + 402))" "$(cat "$home/state/.board-publish-ack")" "ack records its time"
  run_guard "$home" $((P + 5000))
  expect_silent_pass "acknowledged events"
  status_line "$home" alpha "done [at=$((P + 5000))]: a new synthetic outcome"
  run_guard "$home" $((P + 5400))
  expect_code 2 "$status" "a new event after the ack"
  assert_contains "$err" "1 captain-facing" "only the event after the ack counts"
  pass "an ack clears it and the hook never blocks twice for the same events"
}

test_a_captain_branch_outcome_counts() {
  local home
  home=$(make_home)
  printf '%s\n' \
    "{\"seq\":1,\"epoch\":$((P + 30)),\"task\":\"other\",\"wake\":\"signal\",\"verdict\":\"captain\",\"summary\":\"not a second mate\"}" \
    "{\"seq\":2,\"epoch\":$((P + 40)),\"task\":\"alpha\",\"wake\":\"signal\",\"verdict\":\"routine\",\"summary\":\"routine\"}" \
    > "$home/state/branch-outcomes.jsonl"
  run_guard "$home" $((P + 1000))
  expect_silent_pass "a routine row and a row for an unregistered task"
  printf '%s\n' "{\"seq\":3,\"epoch\":$((P + 50)),\"task\":\"alpha\",\"wake\":\"signal\",\"verdict\":\"captain\",\"summary\":\"synthetic\"}" \
    >> "$home/state/branch-outcomes.jsonl"
  run_guard "$home" $((P + 1000))
  expect_code 2 "$status" "a captain row for a second mate"
  pass "a captain branch outcome for a second mate counts and other rows do not"
}

test_non_captain_and_unstamped_lines_are_ignored() {
  local home
  home=$(make_home)
  status_line "$home" alpha "working [at=$((P + 60))]: synthetic progress"
  status_line "$home" alpha "paused [at=$((P + 61))]: synthetic wait"
  status_line "$home" alpha "resolved [key=pick] [at=$((P + 62))]: synthetic resolution"
  status_line "$home" alpha "done: an unstamped synthetic outcome"
  status_line "$home" alpha "done [at=$((P - 60))]: a synthetic outcome before the publish"
  run_guard "$home" $((P + 5000))
  expect_silent_pass "progress, unstamped, and pre-publish lines"
  pass "no captain-facing events passes"
}

test_the_window_comes_from_config() {
  local home
  home=$(make_home)
  status_line "$home" alpha "needs-decision [at=$((P + 60))]: synthetic decision"
  printf '900\n' > "$home/config/board-publish-debounce"
  run_guard "$home" $((P + 60 + 600))
  expect_silent_pass "a 600s-old event under a 900s window"
  run_guard "$home" $((P + 60 + 900))
  expect_code 2 "$status" "a 900s-old event under a 900s window"
  assert_contains "$err" "the oldest from alpha 15 min ago" "a long age reads in minutes"
  printf '5 minutes\n' > "$home/config/board-publish-debounce"
  rm -f "$home/state/.board-publish-nagged"
  run_guard "$home" $((P + 60 + 30))
  expect_code 2 "$status" "an invalid window falls back to 30s"
  assert_contains "$err" "config/board-publish-debounce must be whole seconds; using 30" "an invalid window warns"
  pass "the debounce window comes from config/board-publish-debounce"
}

test_a_second_mate_home_and_a_worker_are_ignored() {
  local home worker
  home=$(make_home)
  status_line "$home" alpha "needs-decision [at=$((P + 60))]: synthetic decision"
  printf 'sm-synthetic\n' > "$home/.fm-secondmate-home"
  run_guard "$home" $((P + 5000))
  expect_silent_pass "a second-mate home"
  rm -f "$home/.fm-secondmate-home"
  worker="$TMP_ROOT/worker"
  git -C "$home" worktree add --quiet -b fm/synthetic-worker "$worker"
  mkdir -p "$worker/bin" "$worker/state" "$worker/data"
  : > "$worker/AGENTS.md"
  cp "$home/data/recap-iterations.jsonl" "$home/data/secondmates.md" "$worker/data/"
  cp "$home/state/alpha.status" "$worker/state/"
  run_guard "$worker" $((P + 5000))
  expect_silent_pass "a task worktree"
  run_guard "$home" $((P + 5000))
  expect_code 2 "$status" "the same events in the main home"
  pass "a second-mate home and a worker are ignored"
}

test_a_home_without_a_board_or_registry_is_ignored() {
  local home
  home=$(make_home)
  status_line "$home" alpha "needs-decision [at=$((P + 60))]: synthetic decision"
  mv "$home/data/secondmates.md" "$home/data/secondmates.off"
  run_guard "$home" $((P + 5000))
  expect_silent_pass "no registry"
  mv "$home/data/secondmates.off" "$home/data/secondmates.md"
  rm "$home/data/recap-iterations.jsonl"
  run_guard "$home" $((P + 5000))
  expect_silent_pass "no iteration log"
  pass "a home that never published a board is ignored"
}

test_an_unreadable_log_steps_aside_with_one_line() {
  local home lines
  home=$(make_home)
  status_line "$home" alpha "needs-decision [at=$((P + 60))]: synthetic decision"
  chmod 000 "$home/state/alpha.status"
  if [ -r "$home/state/alpha.status" ]; then
    chmod 644 "$home/state/alpha.status"
    pass "an unreadable log does not block (skipped: this user reads mode-000 files)"
    return
  fi
  run_guard "$home" $((P + 5000))
  chmod 644 "$home/state/alpha.status"
  expect_code 0 "$status" "an unreadable status log"
  assert_contains "$err" "fm-board-publish-guard: cannot read $home/state/alpha.status" "the stderr line names the log"
  lines=$(printf '%s\n' "$err" | wc -l | tr -d ' ')
  assert_equals 1 "$lines" "exactly one stderr line"
  pass "an unreadable log does not block and prints one stderr line"
}

test_a_lock_refused_session_steps_aside() {
  local home lab owner
  home=$(make_home)
  status_line "$home" alpha "needs-decision [at=$((P + 60))]: synthetic decision"
  lab="$TMP_ROOT/lab"
  mkdir -p "$lab"
  # A process whose argv0 path ends in /claude reads as a live Claude harness,
  # the same stand-in the foreign-owner regression uses; ': ' stops bash from
  # replacing itself with sleep.
  ln -sf /bin/bash "$lab/claude"
  # Its output is detached so the leftover sleep cannot hold the suite's pipe open.
  "$lab/claude" -c 'sleep 60; :' >/dev/null 2>&1 &
  owner=$!
  printf '%s\n' "$owner" > "$home/state/.lock"
  # The hook runs under its own stand-in Claude, so its harness ancestry exists
  # and does not contain the lock owner.
  # shellcheck disable=SC2016 # $1 expands in the inner shell, not here.
  out=$(printf '{}' | FM_ROOT_OVERRIDE="$home" FM_HOME="$home" FM_BOARD_PUBLISH_NOW=$((P + 5000)) \
    "$lab/claude" -c 'bash "$1"; :' guard "$GUARD" 2>"$TMP_ROOT/err")
  status=$?
  err=$(cat "$TMP_ROOT/err")
  pkill -P "$owner" 2>/dev/null
  kill "$owner" 2>/dev/null
  wait "$owner" 2>/dev/null
  expect_silent_pass "another live session holds the home lock"
  rm -f "$home/state/.lock"
  run_guard "$home" $((P + 5000))
  expect_code 2 "$status" "the same home without the foreign lock"
  pass "a session refused the home lock steps aside"
}

test_a_cursor_payload_stands_down() {
  local home
  home=$(make_home)
  status_line "$home" alpha "needs-decision [at=$((P + 60))]: synthetic decision"
  out=$(printf '{"cursor_version":"1.0"}' | FM_ROOT_OVERRIDE="$home" FM_HOME="$home" FM_BOARD_PUBLISH_NOW=$((P + 5000)) \
    bash "$GUARD" 2>"$TMP_ROOT/err")
  status=$?
  err=$(cat "$TMP_ROOT/err")
  expect_silent_pass "a Cursor-delivered duplicate payload"
  pass "a Cursor-delivered duplicate payload stands down"
}

fm_test_run \
  test_an_event_older_than_the_window_blocks \
  test_an_event_inside_the_window_passes_silently \
  test_the_oldest_event_sets_the_debounce \
  test_a_publish_clears_the_block \
  test_a_torn_last_publish_line_falls_back_to_the_previous_one \
  test_an_ack_clears_it_and_it_never_blocks_twice \
  test_a_captain_branch_outcome_counts \
  test_non_captain_and_unstamped_lines_are_ignored \
  test_the_window_comes_from_config \
  test_a_second_mate_home_and_a_worker_are_ignored \
  test_a_home_without_a_board_or_registry_is_ignored \
  test_an_unreadable_log_steps_aside_with_one_line \
  test_a_lock_refused_session_steps_aside \
  test_a_cursor_payload_stands_down
