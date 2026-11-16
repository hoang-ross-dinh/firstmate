#!/usr/bin/env bash
# tests/fm-spawn-claude-session-resume.test.sh - a relaunched claude worker must
# resume the conversation recorded at launch, and fall back to a fresh one with a
# notice when that conversation is gone.
#
# Everything runs against a fake tmux pane and a synthetic Claude config root, so
# no real claude session starts. The assertions read the launch line the pane
# received and the task record, which is what the replacement agent is built from.
set -u

# shellcheck source=tests/fixtures.sh
. "$(dirname "${BASH_SOURCE[0]}")/fixtures.sh"

CONTROL="$ROOT/bin/fm-control.sh"
TMP_ROOT=$(fm_test_tmproot fm-spawn-claude-session)
UUID_RE='[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}'
# Synthetic ids: the test never needs a real session.
OLD_ID=11111111-2222-4333-8444-555555555555

# make_relaunch_stub <case-dir>: just enough pane lifecycle for fm-control's
# exit-then-launch transaction (the harness exit leaves a shell, the launch
# literal starts the agent again).
make_relaunch_stub() {
  local fb="$1/fakebin"
  mkdir -p "$fb"
  cat > "$fb/tmux" <<'SH'
#!/usr/bin/env bash
set -u
D=$FM_FAKE_DIR
case "${1:-}" in
  send-keys)
    shift
    literal=0
    while [ $# -gt 0 ]; do
      case "$1" in
        -t) shift 2 ;;
        -l) literal=1; shift ;;
        *) break ;;
      esac
    done
    payload=${1:-}
    if [ "$literal" = 1 ]; then
      case "$payload" in
        ". '"*"'")
          staged=${payload#". '"}
          staged=${staged%"'"}
          [ ! -f "$staged" ] || payload=$(cat "$staged")
          ;;
      esac
      printf '%s\n' "$payload" >> "$D/literal"
      case "$payload" in
        /exit|/quit) printf 'zsh' > "$D/command" ;;
        *'encode launch-brief'* | *' claude --'*) printf '%s' "${FM_FAKE_AGENT_CMD:-claude}" > "$D/command" ;;
      esac
    else
      printf '%s\n' "$payload" >> "$D/keys"
    fi
    exit 0 ;;
  display-message)
    for a in "$@"; do
      case "$a" in
        *cursor_y*) printf '1\n'; exit 0 ;;
        *pane_current_command*) cat "$D/command"; printf '\n'; exit 0 ;;
        *pane_current_path*) cat "$D/cwd"; printf '\n'; exit 0 ;;
      esac
    done
    printf 'fakepane\n'; exit 0 ;;
  capture-pane) printf '╭────╮\n│    │\n╰────╯\n'; exit 0 ;;
  list-windows) [ -f "$D/windows" ] && cat "$D/windows"; exit 0 ;;
esac
exit 0
SH
  chmod +x "$fb/tmux"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$fb/sleep"
  chmod +x "$fb/sleep"
}

# relaunch_case <name> <prior-harness> <recorded-session-or-empty> <transcript-id-or-empty>
# Runs fm-control relaunch onto claude and leaves RL_OUT, RL_LAUNCH and RL_META.
relaunch_case() {
  local name=$1 prior=$2 recorded=$3 transcript=$4 dir home proj wt id status
  id="session-$name-a1"
  dir="$TMP_ROOT/$name"
  home="$dir/home"
  proj="$dir/proj"
  wt="$dir/wt"
  mkdir -p "$home/state" "$home/data" "$home/config" "$home/projects" "$dir/fake" "$dir/user-home"
  touch "$home/state/.last-watcher-beat"
  make_relaunch_stub "$dir"
  fm_git_worktree "$proj" "$wt" "wt-$name"
  fm_test_spawn_brief "$home" "$id"
  : > "$dir/fake/literal"
  : > "$dir/fake/keys"
  printf 'zsh' > "$dir/fake/command"
  printf '%s\n' "fm-$id" > "$dir/fake/windows"
  printf '%s' "$wt" > "$dir/fake/cwd"
  if [ -n "$transcript" ]; then
    mkdir -p "$dir/user-home/.claude/projects/-synthetic-project"
    : > "$dir/user-home/.claude/projects/-synthetic-project/$transcript.jsonl"
  fi
  {
    echo "window=fmses:fm-$id"
    echo "endpoint_task_id=$id"
    echo "worktree=$wt"
    echo "project=$proj"
    echo "harness=$prior"
    echo "kind=ship"
    echo "mode=no-mistakes"
    echo "yolo=off"
    echo "tasktmp=$dir/tasktmp"
    echo "model=default"
    echo "effort=default"
    [ -z "$recorded" ] || echo "claude_session=$recorded"
  } > "$home/state/$id.meta"
  RL_OUT=$(env PATH="$dir/fakebin:$PATH" FM_HOME="$home" FM_FAKE_DIR="$dir/fake" FM_FAKE_AGENT_CMD=claude \
    HOME="$dir/user-home" CLAUDE_CONFIG_DIR='' FM_SPAWN_NO_GUARD=1 \
    FM_CONTROL_POLL=0.01 FM_CONTROL_EXIT_WAIT=0.05 FM_CONTROL_LAUNCH_WAIT=0.05 \
    "$CONTROL" "$id" relaunch --harness claude --note 'replacement continues the same task' 2>&1)
  status=$?
  expect_code 0 "$status" "relaunch ($name) should succeed: $RL_OUT"
  RL_LAUNCH=$(grep ' claude --' "$dir/fake/literal" | tail -1)
  [ -n "$RL_LAUNCH" ] || fail "relaunch ($name) sent no replacement launch command"
  RL_META="$home/state/$id.meta"
}

meta_session() { sed -n 's/^claude_session=//p' "$1"; }

test_fresh_spawn_records_the_session() {
  local dir home proj wt fakebin launchlog out status id launch recorded
  id=session-fresh-a1
  dir="$TMP_ROOT/fresh"
  home="$dir/home"
  proj="$dir/project"
  wt="$dir/wt"
  launchlog="$dir/launch.log"
  fakebin=$(fm_test_make_spawn_fakebin "$dir/fake")
  fm_test_spawn_home "$home" claude
  fm_git_worktree "$proj" "$wt" wt-fresh
  fm_test_spawn_brief "$home" "$id"
  : > "$launchlog"
  out=$(FM_FAKE_LAUNCH_LOG="$launchlog" FM_FAKE_PANE_LOG="$dir/pane.log" \
    fm_test_run_spawn "$home" "$wt" "$fakebin" "$id" "$proj" --mode no-mistakes --yolo off)
  status=$?
  expect_code 0 "$status" "fresh claude spawn should succeed: $out"
  launch=$(cat "$launchlog")
  recorded=$(meta_session "$home/state/$id.meta")
  [[ "$recorded" =~ ^$UUID_RE$ ]] || fail "fresh spawn must record a UUID claude_session, got '$recorded'"
  case "$launch" in
    *" --session-id $recorded "*) ;;
    *) fail "fresh spawn must launch claude with --session-id $recorded: $launch" ;;
  esac
  case "$launch" in *--resume*) fail "a fresh spawn must never pass --resume" ;; esac
  pass "a fresh claude spawn launches with --session-id and records the same id"
}

test_relaunch_resumes_when_the_transcript_exists() {
  relaunch_case resume claude "$OLD_ID" "$OLD_ID"
  case "$RL_LAUNCH" in
    *" --resume $OLD_ID "*) ;;
    *) fail "relaunch with a surviving transcript must pass --resume $OLD_ID: $RL_LAUNCH" ;;
  esac
  case "$RL_LAUNCH" in *--session-id*) fail "a resumed launch must not also pass --session-id" ;; esac
  assert_equals "$OLD_ID" "$(meta_session "$RL_META")" "a resumed relaunch must keep the recorded id"
  case "$RL_OUT" in *"could not resume"*) fail "a successful resume must print no fallback notice: $RL_OUT" ;; esac
  pass "relaunch passes --resume with the recorded id when its transcript exists"
}

test_relaunch_falls_back_when_the_transcript_is_gone() {
  local new
  relaunch_case gone claude "$OLD_ID" ""
  new=$(meta_session "$RL_META")
  [[ "$new" =~ ^$UUID_RE$ ]] && [ "$new" != "$OLD_ID" ] \
    || fail "a fallback must record a new UUID, got '$new'"
  case "$RL_LAUNCH" in
    *" --session-id $new "*) ;;
    *) fail "fallback must start a fresh conversation with --session-id $new: $RL_LAUNCH" ;;
  esac
  case "$RL_LAUNCH" in *--resume*) fail "fallback must not pass --resume for a missing transcript" ;; esac
  [ "$(printf '%s\n' "$RL_OUT" | grep -c 'could not resume')" = 1 ] \
    || fail "fallback must print exactly one notice line: $RL_OUT"
  pass "relaunch starts a fresh conversation with a notice when the transcript is gone"
}

test_relaunch_falls_back_when_no_id_is_recorded() {
  local new
  relaunch_case noid claude "" ""
  new=$(meta_session "$RL_META")
  [[ "$new" =~ ^$UUID_RE$ ]] || fail "a legacy record must gain a UUID claude_session, got '$new'"
  case "$RL_LAUNCH" in *--resume*) fail "no recorded id means no --resume" ;; esac
  case "$RL_OUT" in *"could not resume"*"no session id recorded"*) ;; *) fail "legacy record must print the fallback notice: $RL_OUT" ;; esac
  pass "relaunch of a record with no session id starts fresh with a notice"
}

test_other_harness_switch_is_silent() {
  relaunch_case switch codex "" ""
  case "$RL_LAUNCH" in *--resume*) fail "a switch from another harness has nothing to resume" ;; esac
  case "$RL_OUT" in *"could not resume"*) fail "a harness switch is not a failed resume and must print no notice: $RL_OUT" ;; esac
  [[ "$(meta_session "$RL_META")" =~ ^$UUID_RE$ ]] || fail "the new claude worker must still record its session id"
  pass "relaunch onto claude from another harness starts fresh without a resume notice"
}

test_fresh_spawn_records_the_session
test_relaunch_resumes_when_the_transcript_exists
test_relaunch_falls_back_when_the_transcript_is_gone
test_relaunch_falls_back_when_no_id_is_recorded
test_other_harness_switch_is_silent
