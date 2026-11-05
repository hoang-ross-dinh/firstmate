#!/usr/bin/env bash
# Behavior tests for the Fleet Recap board: bin/fm-recap-publish.sh (iteration
# log, change-only revisions, torn-line handling, display window) and the
# shipped template (.agents/skills/bearings/assets/recap-board-template.html),
# built through the real `fm-bearings-board.sh build` and executed under the
# DOM shim in tests/assets/recap-render-harness.mjs. Assertions are on the log
# a publish writes and on what the page renders and queues, never on source
# text.
set -u

# shellcheck source=tests/lib.sh
# shellcheck disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

PUBLISH="$ROOT/bin/fm-recap-publish.sh"
HARNESS="$ROOT/tests/assets/recap-render-harness.mjs"
TMP_ROOT=$(fm_test_tmproot fm-recap-publish)

command -v jq >/dev/null 2>&1 || { echo "skip: jq not found"; exit 0; }
command -v node >/dev/null 2>&1 || { echo "skip: node not found"; exit 0; }

make_home() {  # <name>
  local home="$TMP_ROOT/$1" fakebin
  fm_test_track_procevent_home "$home" "$home/procevent-claims"
  mkdir -p "$home/state" "$home/data" "$home/lavish-state"
  fakebin=$(fm_fakebin "$home")
  cat > "$fakebin/lavish-axi" <<'SH'
#!/usr/bin/env bash
case "${1-}" in
  --version) printf '0.1.80\n' ;;
  '')
    printf 'sessions[1]{file,status,url,pending_prompts}:\n'
    [ ! -s "$FM_HOME/lavish-open" ] \
      || printf '  %s,%s,"http://127.0.0.1:4387/session/0123456789abcdef",0\n' "$(cat "$FM_HOME/lavish-open")" "$(cat "$FM_HOME/lavish-listed-status" 2>/dev/null || echo open)"
    ;;
  poll)
    printf 'entered\n' > "$FM_HOME/stub-poll"
    while [ "$SECONDS" -lt "${FM_TEST_STUB_MAX_BLOCK_SECONDS:-120}" ]; do sleep 1; done
    exit 75
    ;;
  *)
    printf '%s\n' "$*" >> "$FM_HOME/lavish-calls"
    real=$(cd "$(dirname "$1")" && pwd -P)/$(basename "$1")
    printf '%s\n' "$real" > "$FM_HOME/lavish-open"
    jq -n --arg file "$real" \
      '{sessions:{"0123456789abcdef":{file:$file,url:"http://127.0.0.1:4387/session/0123456789abcdef"}}}' \
      > "$LAVISH_AXI_STATE_DIR/state.json"
    printf 'session:\n  file: %s\n  url: "http://127.0.0.1:4387/session/0123456789abcdef"\n  status: opened\n' "$real"
    ;;
esac
exit 0
SH
  chmod +x "$fakebin/lavish-axi"
  printf '%s\n' "$home"
}

require_listener_reached_poll() {  # <home>
  local home=$1 i=0 owner=''
  while [ "$i" -lt 40 ]; do
    i=$((i + 1))
    owner=$(home_run "$home" "$ROOT/bin/fm-procevent.sh" list 2>/dev/null | awk 'NR > 1 { print $3; exit }')
    if [ -s "$home/stub-poll" ] && [ "$owner" = live ]; then
      return 0
    fi
    sleep 0.05
  done
  fail "the board listener did not reach the Lavish poll (owner: ${owner:-none})"
}

# Run a command inside the fixture home with every home-scoped override pointed
# at it, so nothing here can reach the operator's real state or data.
home_run() {  # <home> <command...>
  local home=$1
  shift
  PATH="$home/fakebin:$PATH" FM_HOME="$home" \
    FM_STATE_OVERRIDE="$home/state" FM_DATA_OVERRIDE="$home/data" \
    FM_PROCEVENT_CLAIM_ROOT="$home/procevent-claims" \
    LAVISH_AXI_STATE_DIR="$home/lavish-state" \
    FM_RECAP_COLLECT_FILE="$home/collect.json" \
    "$@"
}

# A revision fixture with every stored field defaulted.
rev() {  # <key> <state> <title> [extra-json]
  jq -c -n --arg key "$1" --arg state "$2" --arg title "$3" --argjson extra "${4:-{\}}" '
    {id: ($key | sub("^[^:]*:"; "")), home: (if ($key | contains(":")) then ($key | sub(":.*"; "")) else "main" end),
     kind: "task", repo: "r", state: $state, title: $title, held: false, hold_kind: "", hold_until: "",
     hold_reason: "", blockers: "", pr_url: "", issue_url: "", note: "", waiting: false,
     summary: "s", emoji: "", theme: "T1", reply_terms: [], close: ""} + $extra'
}

# A collected-task fixture (the backlog half of a revision, plus its key).
collected() {  # <key> <state> <title> [extra-json]
  rev "$@" | jq -c --arg key "$1" '. + {key: $key} | del(.summary, .emoji, .theme, .reply_terms, .close)'
}

write_collect() {  # <home> <tasks-json> [warnings-json]
  jq -c -n --argjson tasks "$2" --argjson warnings "${3:-[]}" '{tasks: $tasks, warnings: $warnings}' \
    > "$1/collect.json"
}

write_recap() {  # <home> <tasks-object-json>
  jq -c -n --argjson tasks "$2" '{schema: "fm-recap.v1", tasks: $tasks}' > "$1/recap.json"
}

publish() {  # <home>
  home_run "$1" "$PUBLISH" publish "$1/recap.json"
}

log_of() { printf '%s/data/recap-iterations.jsonl\n' "$1"; }

# A log entry fixture.
entry() {  # <seq> <task-keys-json> <revisions-json> [warnings-json]
  jq -c -n --argjson seq "$1" --argjson tasks "$2" --argjson revisions "$3" --argjson warnings "${4:-[]}" '
    {schema: "fm-recap-iteration.v1", seq: $seq, at: ("2026-10-" + ($seq | tostring | if length < 2 then "0" + . else . end) + "T09:00:00Z"),
     tasks: $tasks, revisions: $revisions, changed_themes: [], waiting: 0, warnings: $warnings}'
}

# Build the board from the log already in the home, then return its path.
refresh_board() {  # <home>
  home_run "$1" "$PUBLISH" refresh >/dev/null || fail "refresh did not build the board"
  require_listener_reached_poll "$1"
  printf '%s/.lavish/bearings-board.html\n' "$1"
}

# The payload a built board's page loads: the sibling data file, unwrapped to JSON.
board_payload() {  # <board>
  sed '1s/^window\.__fmBoard = //;$s/;$//' "${1%/*}/bearings-board.data.js"
}

# Render a built board, optionally driving it with an actions array and a
# sessionStorage file that persists between renders (a reload of the page).
render() {  # <board> [actions-json] [storage-file]
  local board=$1 actions=${2:-} storage=${3:-} file=-
  if [ -n "$actions" ]; then
    file=$(mktemp "$TMP_ROOT/actions.XXXXXX")
    printf '%s' "$actions" > "$file"
  fi
  if [ -n "$storage" ]; then
    node "$HARNESS" "$board" "$file" "$storage" || fail "the board could not be rendered"
  elif [ "$file" != - ]; then
    node "$HARNESS" "$board" "$file" || fail "the board could not be rendered"
  else
    node "$HARNESS" "$board" || fail "the board could not be rendered"
  fi
}

# Everything the page rendered as one string, for substring checks.
all_text() { jq -r '[.nodes[] | select((.cls | test("rb-row__title|rb-rev__head|rb-change|rb-diff|rb-row__mark|rb-older|rb-comment|rb-reply|rb-warn|rb-row__sub|rb-iter__label|rb-empty|fm-badge|rb-group__code|rb-row__badges")))] | map(.text) | join("\n")'; }

# --- iteration log ----------------------------------------------------------

test_each_publish_appends_one_iteration_with_the_next_sequence_number() {
  local home out
  home=$(make_home sequence)
  write_collect "$home" "[$(collected a queued "Task A")]"
  write_recap "$home" '{}'
  out=$(publish "$home") || fail "the first publish failed: $out"
  printf '%s\n' "$out" | grep -qx 'iteration: 1' || fail "the first publish did not report iteration 1: $out"
  out=$(publish "$home") || fail "the second publish failed: $out"
  printf '%s\n' "$out" | grep -qx 'iteration: 2' || fail "the second publish did not report iteration 2: $out"
  [ "$(wc -l < "$(log_of "$home")" | tr -d ' ')" = 2 ] || fail "two publishes did not leave exactly two entries"
  jq -s -e '[.[].seq] == [1, 2]' "$(log_of "$home")" >/dev/null || fail "the sequence numbers were not 1 then 2"
  pass "each publish appends exactly one iteration with the next sequence number"
}

test_the_real_collection_keys_a_task_by_its_bare_id_and_reads_its_quoted_title() {
  local home out
  command -v tasks-axi >/dev/null 2>&1 || { pass "skipped: tasks-axi not found"; return 0; }
  home=$(make_home real-collect)
  mkdir -p "$home/config" "$home/projects"
  fm_test_tasks_toml "$home/.tasks.toml"
  printf '## In flight\n\n## Queued\n\n## Done\n' > "$home/data/backlog.md"
  (cd "$home" && tasks-axi add sample-task "Sample task title" --repo sample >/dev/null) \
    || fail "could not create the backlog task"
  write_recap "$home" '{"sample-task":{"theme":"LW","summary":"matched"}}'
  out=$(home_run "$home" env -u FM_RECAP_COLLECT_FILE FM_CONFIG_OVERRIDE="$home/config" \
    "$PUBLISH" publish "$home/recap.json" 2>&1) || fail "the real-collection publish failed: $out"
  tail -1 "$(log_of "$home")" | jq -e '.tasks == ["sample-task"]
    and .revisions["sample-task"].title == "Sample task title"
    and .revisions["sample-task"].theme == "LW"' >/dev/null \
    || fail "the task key was not its bare id or the recap entry did not match: $(tail -1 "$(log_of "$home")")"
  pass "the real collection keys a task by its bare id and reads its quoted title"
}

test_publish_builds_the_board_while_away_mode_is_active() {
  local home out
  command -v tasks-axi >/dev/null 2>&1 || { pass "skipped: tasks-axi not found"; return 0; }
  home=$(make_home away-publish)
  mkdir -p "$home/config" "$home/projects"
  fm_test_tasks_toml "$home/.tasks.toml"
  printf '## In flight\n\n## Queued\n\n## Done\n' > "$home/data/backlog.md"
  (cd "$home" && tasks-axi add sample-task "Sample task title" --repo sample >/dev/null) \
    || fail "could not create the backlog task"
  printf '1\n' > "$home/state/.afk"
  write_recap "$home" '{"sample-task":{"theme":"LW","summary":"away"}}'
  out=$(home_run "$home" env -u FM_RECAP_COLLECT_FILE FM_CONFIG_OVERRIDE="$home/config" \
    "$PUBLISH" publish "$home/recap.json" 2>&1) || fail "publish failed during an active away window: $out"
  printf '%s\n' "$out" | grep -qx 'iteration: 1' || fail "away publish did not append iteration 1: $out"
  out=$(home_run "$home" env FM_CONFIG_OVERRIDE="$home/config" "$ROOT/bin/fm-bearings-snapshot.sh" --json 2>&1) && \
    fail "plain snapshot did not refuse during an active away window: $out"
  pass "publish builds the board while away mode is active and plain snapshot still refuses"
}

test_a_backlog_change_without_a_publish_creates_no_iteration() {
  local home
  home=$(make_home no-timer)
  write_collect "$home" "[$(collected a queued "Task A")]"
  write_recap "$home" '{}'
  publish "$home" >/dev/null || fail "publish failed"
  write_collect "$home" "[$(collected a in_flight "Task A")]"
  [ "$(wc -l < "$(log_of "$home")" | tr -d ' ')" = 1 ] || fail "a backlog change alone changed the log"
  pass "a backlog change alone creates no iteration"
}

test_only_changed_tasks_get_a_revision() {
  local home out
  home=$(make_home change-only)
  write_collect "$home" "[$(collected a queued "Task A"), $(collected b queued "Task B")]"
  write_recap "$home" '{}'
  publish "$home" >/dev/null || fail "first publish failed"
  write_collect "$home" "[$(collected a in_flight "Task A"), $(collected b queued "Task B")]"
  publish "$home" >/dev/null || fail "second publish failed"
  out=$(tail -1 "$(log_of "$home")")
  printf '%s' "$out" | jq -e '(.revisions | keys) == ["a"] and (.tasks | sort) == ["a", "b"]' >/dev/null \
    || fail "the second entry did not hold one revision and name both tasks: $out"
  pass "only the task whose fields changed gets a new revision"
}

test_a_summary_change_alone_stores_a_revision() {
  local home out
  home=$(make_home summary-only)
  write_collect "$home" "[$(collected a queued "Task A")]"
  write_recap "$home" '{"a":{"summary":"first","emoji":"E1","theme":"LW","reply_terms":["merge"]}}'
  publish "$home" >/dev/null || fail "first publish failed"
  write_recap "$home" '{"a":{"summary":"second"}}'
  publish "$home" >/dev/null || fail "second publish failed"
  out=$(tail -1 "$(log_of "$home")")
  printf '%s' "$out" | jq -e '.revisions.a | .summary == "second" and .emoji == "E1" and .theme == "LW" and .reply_terms == ["merge"]' >/dev/null \
    || fail "the summary change did not store a revision that keeps the other first mate fields: $out"
  pass "a summary change alone stores a revision and keeps the other first mate fields"
}

test_a_revision_stores_every_required_field() {
  local home out
  home=$(make_home fields)
  write_collect "$home" "[$(collected a queued "Task A" '{"hold_reason":"why","blockers":"b","pr_url":"https://example.test/pr/1","issue_url":"https://example.test/i/1","note":"n"}')]"
  write_recap "$home" '{"a":{"summary":"s1","emoji":"E","theme":"LW","reply_terms":["merge"]}}'
  publish "$home" >/dev/null || fail "publish failed"
  out=$(tail -1 "$(log_of "$home")")
  printf '%s' "$out" | jq -e '.revisions.a | [.state,.title,.home,.repo,.hold_reason,.blockers,.pr_url,.issue_url,.note,.summary,.emoji,.theme,.reply_terms] as $v
    | ($v | length) == 13 and ($v | map(. == null) | any | not)' >/dev/null \
    || fail "a revision missed a required field: $out"
  pass "a revision stores every required backlog and first mate field"
}

test_earlier_log_lines_are_never_rewritten() {
  local home before
  home=$(make_home append-only)
  write_collect "$home" "[$(collected a queued "Task A")]"
  write_recap "$home" '{}'
  publish "$home" >/dev/null || fail "first publish failed"
  before=$(cat "$(log_of "$home")")
  write_collect "$home" "[$(collected a 'done' "Task A")]"
  publish "$home" >/dev/null || fail "second publish failed"
  [ "$(head -n 1 "$(log_of "$home")")" = "$before" ] || fail "an earlier log line changed after a later publish"
  pass "earlier log lines stay byte-identical after a later publish"
}

test_a_torn_last_line_is_skipped_reported_and_never_rewritten() {
  local home err out
  home=$(make_home torn
  )
  write_collect "$home" "[$(collected a queued "Task A")]"
  write_recap "$home" '{}'
  publish "$home" >/dev/null || fail "first publish failed"
  printf '{"schema":"fm-recap-iteration.v1","seq":2,"rev' >> "$(log_of "$home")"
  err=$(home_run "$home" "$PUBLISH" read 2>&1 >"$home/read.json") || fail "read failed on a torn line"
  case "$err" in *"skipped 1 unreadable line"*"incomplete last line: yes"*) ;; *) fail "read did not report the torn line: $err" ;; esac
  jq -e 'length == 1 and .[0].seq == 1' "$home/read.json" >/dev/null || fail "read did not return only the intact entry"
  out=$(publish "$home" 2>&1) || fail "publish failed after a torn line: $out"
  printf '%s\n' "$out" | grep -qx 'iteration: 2' || fail "publish did not number the next iteration from the last intact entry: $out"
  grep -q '"seq":2,"rev$' "$(log_of "$home")" || fail "the torn fragment was rewritten or removed"
  [ "$(tail -1 "$(log_of "$home")" | jq -r .seq)" = 2 ] || fail "the new entry did not start on its own line"
  pass "a torn last line is skipped, reported, and never rewritten"
}

test_the_log_lives_in_gitignored_data() {
  local home
  home=$(make_home location)
  [ "$(home_run "$home" "$PUBLISH" path)" = "$home/data/recap-iterations.jsonl" ] \
    || fail "the log path is not under the home's data directory"
  git -C "$ROOT" check-ignore -q data/recap-iterations.jsonl || fail "the log path is not gitignored"
  pass "the iteration log lives in the gitignored data directory"
}

test_an_invalid_recap_publishes_nothing() {
  local home
  home=$(make_home invalid
  )
  write_collect "$home" "[$(collected a queued "Task A")]"
  printf '{"schema":"fm-recap.v1","tasks":{"a":{"theme":"bad theme!"}}}' > "$home/recap.json"
  publish "$home" >/dev/null 2>&1 && fail "an invalid recap published"
  [ ! -e "$(log_of "$home")" ] || fail "an invalid recap wrote the log"
  pass "an invalid recap refuses and writes nothing"
}

# --- board views ------------------------------------------------------------

test_the_display_window_keeps_the_last_30_iterations_and_every_revision_full() {
  local home board out i entries=''
  home=$(make_home window)
  for i in $(seq 1 35); do
    entries="$entries$(entry "$i" '["a"]' "{\"a\": $(rev a queued "Task A" "{\"summary\":\"v$i\"}")}")"$'\n'
  done
  printf '%s' "$entries" > "$(log_of "$home")"
  board=$(refresh_board "$home")
  out=$(board_payload "$board")
  printf '%s' "$out" | jq -e '
    (.tasks[0].revisions | length) == 35 and (.tasks[0] | has("older") | not)
    and (.tasks[0].revisions[-1].summary == "v1") and (.iterations | length) == 30' >/dev/null \
    || fail "the board payload did not keep 30 iterations and every revision in full: $(printf '%s' "$out" | jq -c '[(.tasks[0].revisions|length),(.tasks[0]|has("older")),(.iterations|length)]')"
  [ "$(wc -l < "$(log_of "$home")" | tr -d ' ')" = 35 ] || fail "the display window altered the log"
  pass "the display window shows 30 iterations, every revision stays in full, and the log keeps all"
}

# A task with more revisions than the old 30-iteration tail kept in full, a links
# change near the top and an older tail below: every revision is one card, links
# read as chips, no list or object value shows as JSON, and a long value wraps.
test_every_history_revision_is_one_card_with_readable_values() {
  local home board out i entries='' extra
  home=$(make_home history-cards)
  for i in $(seq 1 36); do
    extra="{\"summary\":\"v$i\",\"reply_terms\":[\"go$i\",\"later\"]"
    [ "$i" -lt 34 ] || extra="$extra,\"links\":$LINKS_FIXTURE"
    extra="$extra}"
    entries="$entries$(entry "$i" '["a"]' "{\"a\": $(rev a queued "Task A" "$extra")}")"$'\n'
  done
  printf '%s' "$entries" > "$(log_of "$home")"
  board=$(refresh_board "$home")
  out=$(render "$board" '[{"click":{"attr":"data-task","value":"a"}}]')
  printf '%s' "$out" | jq -e '.error == ""' >/dev/null || fail "the board errored: $out"
  printf '%s' "$out" | jq -e '[.nodes[] | select(.cls == "rb-rev__head") | .text] | length == 36 and .[0] == "Iteration 36" and .[35] == "Iteration 1"' >/dev/null \
    || fail "not every revision rendered as a card: $(printf '%s' "$out" | jq -c '[.nodes[] | select(.cls == "rb-rev__head") | .text] | length')"
  printf '%s' "$out" | jq -e '[.nodes[] | select(.cls | test("rb-older"))] | length == 0 and ([.nodes[].text] | all(. == null or (test("earlier revisions|^iteration [0-9]+: ") | not)))' >/dev/null \
    || fail "a plain older line or the placeholder card is still rendered"
  printf '%s' "$out" | jq -e '[.nodes[] | select(.text == "first revision")] | length == 1' >/dev/null \
    || fail "only the first revision should read as first revision"
  printf '%s' "$out" | jq -e '[.nodes[] | select(.cls == "rb-change") | .text] | any(test("^links: "))' >/dev/null \
    || fail "the links change is missing from the history"
  printf '%s' "$out" | jq -e '[.nodes[] | select(.cls == "rb-change") | .text] | all(test("[{}\\[\\]\"]") | not)' >/dev/null \
    || fail "a history change shows raw JSON: $(printf '%s' "$out" | jq -c '[.nodes[] | select(.cls == "rb-change") | .text] | map(select(test("[{}\\[\\]\"]")))')"
  printf '%s' "$out" | link_anchors | jq -e '[.[] | select(.cls == "rb-xlink rb-xlink--hist")] | length >= 6 and all(.[]; .attrs.target == "_blank" and .attrs.rel == "noopener noreferrer" and (.attrs.href | startswith("https://example.invalid/")))' >/dev/null \
    || fail "the history links are not chips that open safely: $(printf '%s' "$out" | link_anchors)"
  grep -Eq '\.rb-change \{[^}]*overflow-wrap: anywhere' "$board" || fail "a long history value has no wrap style"
  pass "every history revision is one card, a links change reads as chips, no JSON shows, and long values wrap"
}

seed_views_log() {  # <home>
  local home=$1
  {
    entry 1 '["a","b","c"]' "{
      \"a\": $(rev a queued "Task A" '{"theme":"LW","summary":"A one","emoji":"E"}'),
      \"b\": $(rev b queued "Task B" '{"theme":"QD","summary":"B one"}'),
      \"c\": $(rev c in_flight "Task C" '{"theme":"LW","summary":"C one"}')}"
    entry 2 '["a","b","c"]' "{
      \"a\": $(rev a in_flight "Task A" '{"theme":"LW","summary":"A two","emoji":"E","note":"line one\nline two"}')}"
    entry 3 '["a","b","c"]' "{
      \"b\": $(rev b queued "Task B" '{"theme":"QD","summary":"B one","held":true,"hold_kind":"captain","waiting":true,"hold_reason":"pick one","reply_terms":["go","later"],"close":"release"}'),
      \"a\": $(rev a in_flight "Task A" '{"theme":"LW","summary":"A two","note":"line one\nline three","pr_url":"https://example.test/pr/9","reply_terms":["merge"]}')}"
  } > "$(log_of "$home")"
}

test_a_publish_never_asks_lavish_to_open_a_browser_tab() {
  local home
  home=$(make_home no-open)
  seed_views_log "$home"
  refresh_board "$home" >/dev/null
  write_collect "$home" '[]'
  write_recap "$home" '{}'
  publish "$home" >/dev/null || fail "publish failed"
  [ -s "$home/lavish-calls" ] || fail "the stub saw no establish call"
  ! grep -qv -- '--no-open' "$home/lavish-calls" || fail "a build call omitted --no-open: $(cat "$home/lavish-calls")"
  pass "refresh and publish establish the Lavish session with --no-open"
}

test_a_live_session_listed_with_unread_prompts_is_not_reopened() {
  local home
  home=$(make_home feedback-status)
  seed_views_log "$home"
  printf 'feedback\n' > "$home/lavish-listed-status"
  refresh_board "$home" >/dev/null || fail "a feedback-status session was refused"
  ! grep -q -- '--reopen' "$home/lavish-calls" || fail "a live feedback-status session was reopened: $(cat "$home/lavish-calls")"
  printf 'ended\n' > "$home/lavish-listed-status"
  ! home_run "$home" "$PUBLISH" refresh >/dev/null 2>&1 || fail "an ended-status session was accepted as live"
  pass "a session listed as feedback is live and is not reopened, and an ended one still refuses"
}

label_of() { jq -r '[.nodes[] | select(.cls | test("rb-iter__label")) | .text][0]'; }
badges_of() { jq -c '[.nodes[] | select(.attrs["data-new-iteration"] != null) | .text]'; }

test_a_live_update_keeps_the_readers_place_and_badges_the_new_iteration() {
  local home board storage out
  home=$(make_home live-update)
  seed_views_log "$home"
  storage="$TMP_ROOT/live-update.storage"
  board=$(refresh_board "$home")
  out=$(render "$board")
  [ "$(printf '%s' "$out" | badges_of)" = '[]' ] || fail "a first view showed an arrival badge"
  out=$(render "$board" '[{"click":{"attr":"data-nav","value":"prev"}},{"click":{"attr":"data-task","value":"a"}},{"scroll":240}]' "$storage")
  [ "$(printf '%s' "$out" | label_of)" = "Iteration 2 of 3" ] || fail "setup did not reach iteration 2"
  # A publish adds iteration 4 and Lavish reloads the page: same storage, rebuilt board.
  entry 4 '["a","b","c"]' "{\"a\": $(rev a "done" "Task A" '{"theme":"LW","summary":"A done"}')}" >> "$(log_of "$home")"
  board=$(refresh_board "$home")
  out=$(render "$board" "" "$storage")
  printf '%s' "$out" | jq -e '.error == ""' >/dev/null || fail "the reloaded board errored: $out"
  [ "$(printf '%s' "$out" | label_of)" = "Iteration 2 of 4" ] || fail "the reload left iteration 2: $(printf '%s' "$out" | label_of)"
  printf '%s' "$out" | jq -e '[.nodes[] | select(.tag == "h3") | .text] | any(test("Task A$"))' >/dev/null \
    || fail "the reload dropped the open task detail"
  [ "$(printf '%s' "$out" | jq '.scrolledTo')" = 240 ] || fail "the reload did not restore the scroll position"
  [ "$(printf '%s' "$out" | badges_of)" = '["Iteration 4 arrived"]' ] || fail "no arrival badge after the update: $(printf '%s' "$out" | badges_of)"
  # Reloading again with nothing new keeps the badge until the newest iteration is viewed.
  out=$(render "$board" "" "$storage")
  [ "$(printf '%s' "$out" | badges_of)" = '["Iteration 4 arrived"]' ] || fail "the badge vanished before the newest iteration was viewed"
  # Clicking it switches to the new iteration and clears it.
  out=$(render "$board" '[{"click":{"attr":"data-new-iteration","value":"4"}}]' "$storage")
  [ "$(printf '%s' "$out" | label_of)" = "Iteration 4 of 4" ] || fail "the badge did not switch to iteration 4"
  [ "$(printf '%s' "$out" | badges_of)" = '[]' ] || fail "the badge stayed after viewing the newest iteration"
  out=$(render "$board" "" "$storage")
  [ "$(printf '%s' "$out" | badges_of)" = '[]' ] && [ "$(printf '%s' "$out" | label_of)" = "Iteration 4 of 4" ] \
    || fail "the cleared badge returned or the view moved on reload"
  pass "a live update keeps the view and place, badges the new iteration, and clears it once viewed"
}

test_the_board_renders_without_session_storage() {
  local home board out
  home=$(make_home no-storage)
  seed_views_log "$home"
  board=$(refresh_board "$home")
  out=$(render "$board")
  printf '%s' "$out" | jq -e '.error == "" and ([.nodes[] | select(.cls | test("rb-iter__label")) | .text] == ["Iteration 3 of 3"])' >/dev/null \
    || fail "the board did not render without sessionStorage: $out"
  pass "the board renders with no sessionStorage"
}

test_the_built_board_opens_in_explore_mode() {
  local home board
  home=$(make_home explore)
  seed_views_log "$home"
  board=$(refresh_board "$home")
  [ "$(node -e '
    const html = require("fs").readFileSync(process.argv[1], "utf8");
    const tag = html.match(/<html\b[^>]*>/i);
    process.stdout.write(tag && /\sdata-lavish-annotate="off"/.test(tag[0]) ? "off" : "missing");
  ' "$board")" = off ] || fail "the built board's html element does not open in explore mode"
  pass "the built board opens in explore mode"
}

test_the_iteration_view_groups_by_theme_and_marks_each_task() {
  local home board out
  home=$(make_home groups)
  seed_views_log "$home"
  board=$(refresh_board "$home")
  out=$(render "$board")
  printf '%s' "$out" | jq -e '.error == ""' >/dev/null || fail "the board rendered an error: $out"
  printf '%s' "$out" | jq -e '[.nodes[] | select(.cls | test("rb-group__code")) | .text] == ["LW", "QD"]' >/dev/null \
    || fail "the tasks were not grouped by theme code: $(printf '%s' "$out" | all_text)"
  printf '%s' "$out" | all_text | grep -q 'unchanged since iteration 1' || fail "an unchanged task was not marked with its source iteration"
  printf '%s' "$out" | all_text | grep -q 'new in this iteration' || fail "a changed task was not marked new"
  pass "the iteration view groups tasks by theme and marks new or unchanged since iteration N"
}

test_rows_and_groups_are_ordered_by_priority_emoji() {
  local home board out red=$'\xF0\x9F\x94\xB4' yel=$'\xF0\x9F\x9F\xA1' grn=$'\xF0\x9F\x9F\xA2'
  home=$(make_home priority)
  {
    entry 1 '["a","b","c","d","e"]' "{
      \"a\": $(rev a queued "Task A" "{\"theme\":\"AA\",\"emoji\":\"$grn\"}"),
      \"b\": $(rev b queued "Task B" "{\"theme\":\"ZZ\",\"emoji\":\"$grn\"}"),
      \"c\": $(rev c queued "Task C" "{\"theme\":\"ZZ\",\"emoji\":\"$red\"}"),
      \"d\": $(rev d queued "Task D" "{\"theme\":\"ZZ\",\"emoji\":\"$yel\"}"),
      \"e\": $(rev e queued "Task E" '{"theme":"MM"}')}"
  } > "$(log_of "$home")"
  board=$(refresh_board "$home")
  out=$(render "$board")
  printf '%s' "$out" | jq -e '[.nodes[] | select(.cls | test("rb-group__code")) | .text] == ["ZZ", "AA", "MM"]' >/dev/null \
    || fail "the groups were not ordered by best priority: $(printf '%s' "$out" | all_text)"
  printf '%s' "$out" | jq -e '[.nodes[] | select(.attrs["data-task"] != null) | .attrs["data-task"]] == ["c","d","b","a","e"]' >/dev/null \
    || fail "the rows were not ordered by priority inside their groups"
  pass "rows and theme groups are ordered by priority emoji from high to low"
}

test_the_filters_narrow_the_iteration_view() {
  local home board out
  home=$(make_home filters)
  seed_views_log "$home"
  board=$(refresh_board "$home")
  out=$(render "$board" '[{"click":{"attr":"data-filter","value":"waiting"}}]')
  printf '%s' "$out" | jq -e '[.nodes[] | select(.attrs["data-task"] != null) | .attrs["data-task"]] == ["b"]' >/dev/null \
    || fail "Waiting on you did not list only the held task: $(printf '%s' "$out" | all_text)"
  out=$(render "$board" '[{"click":{"attr":"data-filter","value":"changed"}}]')
  printf '%s' "$out" | jq -e '[.nodes[] | select(.attrs["data-task"] != null) | .attrs["data-task"]] | sort == ["a","b"]' >/dev/null \
    || fail "Changed in this iteration did not list the tasks revised in iteration 3"
  printf '%s' "$out" | jq -e '[.nodes[] | select(.attrs["data-filter"] != null) | .text] == ["Open (3)","Changed in this iteration (2)","Waiting on you (1)","All (3)"]' >/dev/null \
    || fail "the four filters were not offered with counts"
  pass "the four filters narrow the iteration view"
}

test_the_captain_can_move_between_iterations() {
  local home board out
  home=$(make_home navigation)
  seed_views_log "$home"
  board=$(refresh_board "$home")
  out=$(render "$board" '[{"click":{"attr":"data-nav","value":"prev"}},{"click":{"attr":"data-nav","value":"prev"}}]')
  printf '%s' "$out" | jq -e '
    ([.nodes[] | select(.cls | test("rb-iter__label")) | .text] == ["Iteration 1 of 3"])
    and ([.nodes[] | select(.attrs["data-nav"] == "prev") | .disabled] == [true])
    and ([.nodes[] | select(.attrs["data-nav"] == "next") | .disabled] == [false])' >/dev/null \
    || fail "previous did not reach iteration 1: $out"
  printf '%s' "$out" | all_text | grep -q 'new in this iteration' || fail "iteration 1 did not mark its tasks new"
  out=$(render "$board")
  printf '%s' "$out" | jq -e '[.nodes[] | select(.attrs["data-nav"] == "next") | .disabled] == [true]' >/dev/null \
    || fail "next was not disabled on the newest iteration"
  pass "previous and next move between iterations and stop at the ends"
}

test_a_finished_task_stays_three_iterations_then_hides_but_remains_reachable() {
  local home board out i
  home=$(make_home finished
  )
  {
    entry 1 '["a","d"]' "{\"a\": $(rev a queued "Task A"), \"d\": $(rev d in_flight "Task D")}"
    entry 2 '["a","d"]' "{\"d\": $(rev d 'done' "Task D")}"
    for i in 3 4 5 6; do entry "$i" '["a","d"]' '{}'; done
  } > "$(log_of "$home")"
  board=$(refresh_board "$home")
  out=$(render "$board" '[{"click":{"attr":"data-nav","value":"prev"}}]')
  printf '%s' "$out" | jq -e '[.nodes[] | select(.attrs["data-task"] != null) | .attrs["data-task"]] | index("d") != null' >/dev/null \
    || fail "the finished task left the default list within 3 iterations of finishing"
  out=$(render "$board")
  printf '%s' "$out" | jq -e '[.nodes[] | select(.attrs["data-task"] != null) | .attrs["data-task"]] == ["a"]' >/dev/null \
    || fail "the finished task stayed in the default list after 3 iterations"
  out=$(render "$board" '[{"click":{"attr":"data-filter","value":"all"}},{"click":{"attr":"data-task","value":"d"}}]')
  printf '%s' "$out" | jq -e '[.nodes[] | select(.tag == "h3") | .text] | index("Task D") != null' >/dev/null \
    || fail "the hidden task's detail was not reachable through All"
  pass "a finished task stays in the default list for 3 iterations, then hides, and All and its detail still show it"
}

test_the_task_detail_shows_newest_first_history_with_field_and_note_diffs() {
  local home board out
  home=$(make_home detail)
  seed_views_log "$home"
  board=$(refresh_board "$home")
  out=$(render "$board" '[{"click":{"attr":"data-task","value":"a"}}]')
  printf '%s' "$out" | jq -e '[.nodes[] | select(.cls | test("rb-rev__head")) | .text] == ["Iteration 3","Iteration 2","Iteration 1"]' >/dev/null \
    || fail "the history was not listed newest first: $(printf '%s' "$out" | all_text)"
  printf '%s' "$out" | jq -e '[.nodes[] | select(.cls | test("rb-change")) | .text] | any(test("state: queued -> in_flight"))' >/dev/null \
    || fail "the history did not show the state change with old and new value"
  out=$(render "$board" '[{"click":{"attr":"data-task","value":"a"}},{"click":{"text":"Show note diff"}}]')
  printf '%s' "$out" | jq -e '[.nodes[] | select(.cls | test("rb-diff__add|rb-diff__del")) | .text] | sort == ["+ line three","- line two"]' >/dev/null \
    || fail "the note diff did not show the removed and added lines: $(printf '%s' "$out" | jq -c '[.nodes[]|select(.cls|test("rb-diff"))|.text]')"
  pass "the task detail shows newest-first history with field changes and a note diff"
}

test_a_task_detail_opens_as_a_panel_over_the_list_without_moving_the_list() {
  local home board out rows
  home=$(make_home panel-open)
  seed_views_log "$home"
  board=$(refresh_board "$home")
  rows=$(render "$board" | jq '[.nodes[] | select(.attrs["data-task"] != null)] | length')
  out=$(render "$board" '[{"scroll":600},{"click":{"attr":"data-task","value":"a"}}]')
  printf '%s' "$out" | jq -e '.error == "" and .scrollY == 600' >/dev/null     || fail "opening a task moved the list scroll position: $out"
  printf '%s' "$out" | jq -e --argjson rows "$rows" '
    ([.nodes[] | select(.attrs.id == "rb-panel") | .hidden] == [false])
    and ([.nodes[] | select(.attrs["data-task"] != null)] | length) == $rows
    and ([.nodes[] | select(.cls | test("rb-drawer__head")) | .text] | any(test("Task A")))' >/dev/null     || fail "the task did not open in a panel beside the still-rendered list"
  pass "a task detail opens as a panel over the list and leaves the list scroll position alone"
}

test_the_panel_closes_with_its_close_button_or_escape_and_keeps_the_list_scroll() {
  local home board out
  home=$(make_home panel-close)
  seed_views_log "$home"
  board=$(refresh_board "$home")
  out=$(render "$board" '[{"scroll":600},{"click":{"attr":"data-task","value":"a"}},{"click":{"attr":"data-close","value":"1"}}]')
  printf '%s' "$out" | jq -e '.error == "" and .scrollY == 600 and ([.nodes[] | select(.attrs.id == "rb-panel") | .hidden] == [true])' >/dev/null     || fail "the close button did not close the panel or moved the list: $out"
  out=$(render "$board" '[{"scroll":600},{"click":{"attr":"data-task","value":"a"}},{"key":"Escape"}]')
  printf '%s' "$out" | jq -e '.error == "" and .scrollY == 600 and ([.nodes[] | select(.attrs.id == "rb-panel") | .hidden] == [true])' >/dev/null     || fail "Escape did not close the panel or moved the list: $out"
  out=$(render "$board" '[{"click":{"attr":"data-task","value":"a"}},{"click":{"attr":"data-close","value":"1"}},{"click":{"attr":"data-task","value":"b"}}]')
  printf '%s' "$out" | jq -e '[.nodes[] | select(.cls | test("rb-drawer__head")) | .text] | any(test("Task B"))' >/dev/null     || fail "a task could not be opened again after closing"
  pass "the panel closes with its close button or Escape and the list keeps its scroll position"
}

# Lavish flags text that an opaque panel covers as a layout issue. A queued layout issue
# blocks every Send to Agent once the page reloads (Lavish 0.1.96), so the open panel must
# clip the page behind it rather than paint over it.
test_the_open_panel_clips_the_page_behind_it_so_no_text_is_covered() {
  local home board out page
  home=$(make_home panel-clip)
  seed_views_log "$home"
  board=$(refresh_board "$home")
  grep -q '\.rb-page--covered { clip-path: inset(0 var(--rb-drawer-w) 0 0)' "$board" \
    || fail "the board has no clip rule for the page behind the open panel"
  page='[.nodes[] | select(.attrs.id == "rb-page") | .cls]'
  out=$(render "$board" '[]')
  printf '%s' "$out" | jq -e "$page == [\"rb-page\"]" >/dev/null || fail "the page is clipped while no panel is open: $out"
  out=$(render "$board" '[{"click":{"attr":"data-task","value":"a"}}]')
  printf '%s' "$out" | jq -e "$page == [\"rb-page rb-page--covered\"]" >/dev/null \
    || fail "the page behind the open panel is not clipped: $(printf '%s' "$out" | jq -c "$page")"
  out=$(render "$board" '[{"click":{"attr":"data-task","value":"a"}},{"click":{"attr":"data-close","value":"1"}}]')
  printf '%s' "$out" | jq -e "$page == [\"rb-page\"]" >/dev/null || fail "the close button left the page clipped"
  out=$(render "$board" '[{"click":{"attr":"data-task","value":"a"}},{"key":"Escape"}]')
  printf '%s' "$out" | jq -e "$page == [\"rb-page\"]" >/dev/null || fail "Escape left the page clipped"
  pass "the open panel clips the page behind it and the clip clears when the panel closes"
}

test_panel_page_keys_scroll_the_panel_and_leave_editing_keys_to_the_comment_field() {
  local home board out open poll
  home=$(make_home panel-keys)
  seed_views_log "$home"
  board=$(refresh_board "$home")
  open='{"click":{"attr":"data-task","value":"a"}}'
  out=$(render "$board" "[$open,{\"keyin\":{\"key\":\"Home\",\"name\":\"comment\"}},{\"keyin\":{\"key\":\"End\",\"name\":\"comment\"}}]")
  printf '%s' "$out" | jq -e '.error == "" and ([.keys[] | select(.prevented)] | length) == 0 and ([.nodes[] | select(.cls | test("rb-drawer__body")) | .scrollTop] == [0])' >/dev/null \
    || fail "Home or End in the comment field was intercepted or scrolled the panel: $out"
  out=$(render "$board" "[$open,{\"keyin\":{\"key\":\"PageDown\",\"name\":\"comment\"}},{\"keyin\":{\"key\":\"PageUp\",\"name\":\"comment\"}}]")
  printf '%s' "$out" | jq -e '.error == "" and ([.keys[] | select(.prevented)] | length) == 0 and ([.nodes[] | select(.cls | test("rb-drawer__body")) | .scrollTop] == [0])' >/dev/null \
    || fail "PageUp or PageDown in the comment field was intercepted or scrolled the panel: $out"
  out=$(render "$board" "[$open,{\"key\":\"PageDown\"},{\"key\":\"PageDown\"},{\"key\":\"PageUp\"},{\"key\":\"Home\"},{\"key\":\"End\"}]")
  printf '%s' "$out" | jq -e '.error == "" and ([.nodes[] | select(.cls | test("rb-drawer__body")) | .scrollTop] == [900])
    and ([.keys[] | select(.key == "Home" or .key == "End") | .prevented] == [false, false])' >/dev/null \
    || fail "PageDown and PageUp did not scroll the panel by a page, or Home and End were bound: $out"
  pass "PageUp and PageDown scroll the panel outside a field, and Home, End and the page keys stay native in the comment field"
}

test_the_panel_header_pins_the_title_and_close_button_and_the_back_link_is_gone() {
  local home board out
  home=$(make_home panel-head)
  seed_views_log "$home"
  board=$(refresh_board "$home")
  out=$(render "$board" '[{"click":{"attr":"data-task","value":"a"}}]')
  printf '%s' "$out" | jq -e '[.nodes[] | select(.cls | test("rb-drawer__head")) | .text] | any(test("Task A") and test("Close$"))' >/dev/null     || fail "the panel header did not hold the title and the close button"
  printf '%s' "$out" | jq -e '
    ([.nodes[] | select(.attrs["data-back"] != null)] | length) == 0
    and ([.nodes[] | select(.text | test("^Back to"))] | length) == 0' >/dev/null     || fail "the Back to iteration link is still on the detail view"
  pass "the panel header pins the title and close button, and the Back to iteration link is gone"
}

test_a_freshly_loaded_board_starts_with_the_panel_closed_and_the_list_rendered() {
  local home board out
  home=$(make_home panel-reload)
  seed_views_log "$home"
  board=$(refresh_board "$home")
  out=$(render "$board")
  printf '%s' "$out" | jq -e '
    .error == ""
    and ([.nodes[] | select(.attrs.id == "rb-panel") | .hidden] == [true])
    and ([.nodes[] | select(.attrs["data-task"] != null)] | length) > 0' >/dev/null     || fail "a fresh load did not start with the panel closed and the list shown: $out"
  pass "a freshly loaded board starts with the panel closed and the list rendered"
}

test_a_jira_key_links_only_through_the_private_base_setting() {
  local home board out base='https://jira.example.test/browse/'
  home=$(make_home jira)
  mkdir -p "$home/config"
  {
    entry 1 '["a"]' "{\"a\": $(rev a queued "ABC-123 Task A" '{"note":"see ABC-123"}')}"
  } > "$(log_of "$home")"
  board=$(refresh_board "$home")
  out=$(render "$board" '[{"click":{"attr":"data-task","value":"a"}}]')
  printf '%s' "$out" | jq -e '([.nodes[] | select(.tag == "a")] | length == 0) and ([.nodes[] | select(.tag == "span" and .text == "ABC-123")] | length == 1)' >/dev/null \
    || fail "an unset base did not leave the key as plain text: $out"
  printf '%s\n' "$base" > "$home/config/recap-jira-base"
  board=$(refresh_board "$home")
  out=$(render "$board" '[{"click":{"attr":"data-task","value":"a"}}]')
  printf '%s' "$out" | jq -e --arg href "${base}ABC-123" '[.nodes[] | select(.tag == "a") | .attrs.href] == [$href]' >/dev/null \
    || fail "the configured base did not make the key a single link: $out"
  printf '%s\n' 'javascript:alert(1)//' > "$home/config/recap-jira-base"
  board=$(refresh_board "$home")
  out=$(render "$board" '[{"click":{"attr":"data-task","value":"a"}}]')
  printf '%s' "$out" | jq -e '[.nodes[] | select(.tag == "a")] | length == 0' >/dev/null \
    || fail "a non-https base produced a link: $out"
  pass "a Jira key links only through the private base setting"
}

test_warnings_have_their_own_section_and_never_count_as_work() {
  local home board out
  home=$(make_home warnings)
  {
    entry 1 '["a"]' "{\"a\": $(rev a queued "Task A")}" '[{"id":"(main-inventory)","title":"Main inventory integrity","reason":"orphaned row"}]'
  } > "$(log_of "$home")"
  board=$(refresh_board "$home")
  out=$(render "$board")
  printf '%s' "$out" | jq -e '
    ([.nodes[] | select(.cls | test("rb-warn")) | .text] | length) == 1
    and ([.nodes[] | select(.attrs["data-task"] != null)] | length) == 1
    and ([.nodes[] | select(.attrs["data-filter"] == "open") | .text] == ["Open (1)"])' >/dev/null \
    || fail "the warning was not shown apart from the task list: $(printf '%s' "$out" | all_text)"
  pass "fleet-integrity warnings render in their own section and never count as queued work"
}

# --- actions ----------------------------------------------------------------

test_a_main_home_hold_queues_its_answer_for_the_captain_hold_intake() {
  local home board out
  home=$(make_home answer)
  seed_views_log "$home"
  board=$(refresh_board "$home")
  out=$(render "$board" '[{"click":{"attr":"data-task","value":"b"}},{"check":{"value":"go"}},{"submit":{"question":"b"}}]')
  printf '%s' "$out" | jq -e '.queued | length == 1 and (.[0] | .tag == "choice" and .question == "b"
    and .data.schema == "fm-bearings-answer.v1" and .data.question == "b" and .data.selection == "go" and .data.close == "release")' >/dev/null \
    || fail "the hold answer was not queued as a keyed answer: $(printf '%s' "$out" | jq -c .queued)"
  pass "a main-home hold answer queues as a keyed answer for the captain-hold intake"
}

test_a_secondmate_card_offers_answer_buttons_and_names_who_acts() {
  local home board out
  home=$(make_home relay-card)
  {
    entry 1 '["pm:x"]' "{\"pm:x\": $(rev pm:x queued "Mate task" '{"held":true,"hold_kind":"captain","waiting":true,"hold_reason":"pick","reply_terms":["go","later"]}')}"
  } > "$(log_of "$home")"
  board=$(refresh_board "$home")
  out=$(render "$board" '[{"click":{"attr":"data-task","value":"pm:x"}}]')
  printf '%s' "$out" | all_text | grep -q 'Answer goes to pm through the first mate' || fail "the card did not name who acts"
  printf '%s' "$out" | jq -e '[.nodes[] | select(.text | test("answer in chat"; "i"))] | length == 0' >/dev/null     || fail "the card still tells the captain to answer in chat"
  out=$(render "$board" '[{"click":{"attr":"data-task","value":"pm:x"}},{"check":{"value":"go"}},{"submit":{"question":"answer.pm-x"}}]')
  printf '%s' "$out" | jq -e '.error == "" and (.queued | length == 1 and (.[0] | .tag == "choice"
    and .data.schema == "fm-bearings-comment.v1" and .data.kind == "answer" and .data.task == "pm:x" and .data.text == "go"))' >/dev/null     || fail "the secondmate answer was not queued as a relayed answer: $(printf '%s' "$out" | jq -c '[.error, .queued]')"
  printf '%s' "$out" | jq -e '[.nodes[] | select(.tag == "label") | .text] | index("reconcile") == null and index("Reconcile") == null' >/dev/null \
    || fail "a secondmate card offered the main-home reconcile choice"
  pass "a secondmate card offers answer buttons, names who acts, and queues a relayed answer"
}

test_a_blocked_task_shows_a_blocked_badge_and_its_blockers_and_an_unblocked_task_shows_none() {
  local home board out
  home=$(make_home blocked-badge)
  {
    entry 1 '["a","b"]' "{
      \"a\": $(rev a queued "Task A" '{"blockers":"dep-1,dep-2"}'),
      \"b\": $(rev b queued "Task B")}"
  } > "$(log_of "$home")"
  board=$(refresh_board "$home")
  out=$(render "$board")
  printf '%s' "$out" | jq -e '[.nodes[] | select(.cls | test("fm-badge")) | .text] | map(select(. == "blocked")) | length == 1' >/dev/null \
    || fail "exactly the blocked task did not get one blocked badge: $(printf '%s' "$out" | all_text)"
  printf '%s' "$out" | all_text | grep -q 'blocked by dep-1,dep-2' || fail "the row did not name the blocker ids"
  out=$(render "$board" '[{"click":{"attr":"data-task","value":"a"}}]')
  printf '%s' "$out" | jq -e '[.nodes[] | select(.cls | test("fm-badge")) | .text] | map(select(. == "blocked")) | length == 2' >/dev/null \
    || fail "the detail panel did not show the blocked badge"
  printf '%s' "$out" | jq -e '[.nodes[] | select(.cls | test("rb-row__sub")) | .text] | map(select(. == "blocked by dep-1,dep-2")) | length == 2' >/dev/null \
    || fail "the detail panel did not show the blocker ids"
  out=$(render "$board" '[{"click":{"attr":"data-task","value":"b"}}]')
  printf '%s' "$out" | jq -e '[.nodes[] | select(.cls | test("fm-badge")) | .text] | map(select(. == "blocked")) | length == 1' >/dev/null \
    || fail "an unblocked task detail showed a blocked badge beyond task A's row"
  pass "a blocked task shows a blocked badge and its blocker ids in the row and the detail, and an unblocked task shows none"
}

test_the_detail_state_badge_matches_the_row_tone_and_the_theme_code_reads_as_a_recap_label() {
  local home board out
  home=$(make_home state-tone)
  {
    entry 1 '["a"]' "{
      \"a\": $(rev a in_flight "Task A")}"
  } > "$(log_of "$home")"
  board=$(refresh_board "$home")
  out=$(render "$board" '[{"click":{"attr":"data-task","value":"a"}}]')
  printf '%s' "$out" | jq -e '[.nodes[] | select(.cls | test("fm-badge--online")) | .text] == ["in_flight", "in_flight"]' >/dev/null \
    || fail "the row and the detail did not both show in_flight in the online tone"
  printf '%s' "$out" | jq -e '[.nodes[] | select(.cls | test("fm-badge--info")) | .text] | index("in_flight") == null' >/dev/null \
    || fail "the detail showed in_flight in the info tone"
  printf '%s' "$out" | jq -e '[.nodes[] | select(.cls | test("fm-badge--solid"))] | length == 0' >/dev/null \
    || fail "a solid theme-code badge remained"
  printf '%s' "$out" | jq -e '[.nodes[] | select(.cls | test("fm-badge--neutral")) | .text] | index("Recap T1") != null' >/dev/null \
    || fail "the detail did not label the theme code as Recap T1"
  pass "the detail state badge matches the row tone and the theme code reads as a neutral Recap label"
}

test_a_secondmate_home_task_with_blockers_shows_the_blocked_badge() {
  local home board out
  home=$(make_home blocked-mate)
  {
    entry 1 '["pm:x","pm:y"]' "{
      \"pm:x\": $(rev pm:x queued "Mate queued task" '{"blockers":"pm-dep"}'),
      \"pm:y\": $(rev pm:y queued "Mate held task" '{"blockers":"pm-dep","held":true,"hold_kind":"external","hold_reason":"wait"}')}"
  } > "$(log_of "$home")"
  board=$(refresh_board "$home")
  out=$(render "$board")
  printf '%s' "$out" | jq -e '[.nodes[] | select(.cls | test("fm-badge")) | .text] | map(select(. == "blocked")) | length == 2' >/dev/null \
    || fail "a secondmate-home task with blockers did not show the blocked badge: $(printf '%s' "$out" | all_text)"
  printf '%s' "$out" | all_text | grep -q 'blocked by pm-dep' || fail "the secondmate-home row did not name its blocker"
  pass "a secondmate-home task with blockers shows the blocked badge, queued or held"
}

test_on_hold_is_stored_kept_cleared_and_a_bad_value_publishes_nothing() {
  local home out bad
  home=$(make_home on-hold-publish)
  write_collect "$home" "[$(collected a queued "Task A"), $(collected b queued "Task B")]"
  write_recap "$home" '{"a":{"on_hold":"waiting: first review feedback"}}'
  publish "$home" >/dev/null || fail "a publish with on_hold failed"
  out=$(tail -1 "$(log_of "$home")")
  printf '%s' "$out" | jq -e '.revisions.a.on_hold == "waiting: first review feedback" and (.revisions.b | has("on_hold") | not)' >/dev/null     || fail "on_hold was not stored on the marked task alone: $out"
  write_recap "$home" '{"a":{"summary":"later"}}'
  publish "$home" >/dev/null || fail "a publish without on_hold failed"
  tail -1 "$(log_of "$home")" | jq -e '.revisions.a.on_hold == "waiting: first review feedback"' >/dev/null     || fail "an omitted on_hold did not keep its last value"
  write_recap "$home" '{"a":{"on_hold":""}}'
  publish "$home" >/dev/null || fail "a publish clearing on_hold failed"
  tail -1 "$(log_of "$home")" | jq -e '.revisions.a | has("on_hold") | not' >/dev/null     || fail "an empty on_hold did not clear the mark"
  for bad in '{"a":{"on_hold":true}}' '{"a":{"on_hold":3}}' '{"a":{"on_hold":["x"]}}' \
    "{\"a\":{\"on_hold\":\"$(printf 'x%.0s' $(seq 1 201))\"}}"; do
    printf '{"schema":"fm-recap.v1","tasks":%s}' "$bad" > "$home/recap.json"
    publish "$home" >/dev/null 2>&1 && fail "a bad on_hold published: $bad"
  done
  [ "$(wc -l < "$(log_of "$home")" | tr -d ' ')" = 3 ] || fail "a bad on_hold wrote the log"
  pass "on_hold is stored, kept when omitted, cleared by an empty string, and a bad value publishes nothing"
}

test_an_on_hold_task_shows_an_on_hold_badge_and_its_event_and_an_unmarked_task_shows_none() {
  local home board out
  home=$(make_home on-hold-badge)
  entry 1 '["a","b"]' "{
    \"a\": $(rev a queued "Task A" '{"on_hold":"waiting: first review feedback"}'),
    \"b\": $(rev b queued "Task B")}" > "$(log_of "$home")"
  board=$(refresh_board "$home")
  out=$(render "$board")
  printf '%s' "$out" | jq -e '[.nodes[] | select(.cls | test("fm-badge")) | .text] | map(select(. == "On Hold")) | length == 1' >/dev/null     || fail "exactly the marked task did not get one On Hold badge: $(printf '%s' "$out" | all_text)"
  printf '%s' "$out" | jq -e '[.nodes[] | select(.cls | test("fm-badge--hold")) | .text] == ["On Hold"]' >/dev/null     || fail "the On Hold badge shares a tone with another badge"
  printf '%s' "$out" | all_text | grep -qx 'waiting: first review feedback' || fail "the row did not show the event text"
  out=$(render "$board" '[{"click":{"attr":"data-task","value":"a"}}]')
  printf '%s' "$out" | jq -e '[.nodes[] | select(.cls | test("fm-badge")) | .text] | map(select(. == "On Hold")) | length == 2' >/dev/null     || fail "the detail panel did not show the On Hold badge"
  printf '%s' "$out" | jq -e '[.nodes[] | select(.cls | test("rb-row__sub")) | .text] | map(select(. == "waiting: first review feedback")) | length == 2' >/dev/null     || fail "the detail panel did not show the event text"
  out=$(render "$board" '[{"click":{"attr":"data-task","value":"b"}}]')
  printf '%s' "$out" | jq -e '[.nodes[] | select(.cls | test("fm-badge")) | .text] | map(select(. == "On Hold")) | length == 1' >/dev/null     || fail "an unmarked task detail showed an On Hold badge beyond task A's row"
  pass "an on-hold task shows an On Hold badge and its event on the row and the detail, and an unmarked task shows none"
}

test_a_task_both_blocked_and_on_hold_shows_both_badges() {
  local home board out
  home=$(make_home on-hold-blocked)
  entry 1 '["a"]' "{\"a\": $(rev a queued "Task A" '{"on_hold":"waiting: review","blockers":"dep-1"}')}" > "$(log_of "$home")"
  board=$(refresh_board "$home")
  out=$(render "$board")
  printf '%s' "$out" | jq -e '[.nodes[] | select(.cls | test("fm-badge")) | .text] | (index("On Hold") != null) and (index("blocked") != null)' >/dev/null     || fail "a blocked and on-hold task did not show both badges: $(printf '%s' "$out" | all_text)"
  printf '%s' "$out" | all_text | grep -q 'blocked by dep-1' || fail "the blocker ids vanished beside the On Hold badge"
  pass "a task both blocked and on hold shows both badges"
}

test_the_on_hold_text_is_escaped_and_a_history_change_reads_as_text() {
  local home board out
  home=$(make_home on-hold-history)
  entry 1 '["a"]' "{\"a\": $(rev a queued "Task A")}" > "$(log_of "$home")"
  entry 2 '["a"]' "{\"a\": $(rev a queued "Task A" '{"on_hold":"<img src=x onerror=alert(1)> waiting"}')}" >> "$(log_of "$home")"
  entry 3 '["a"]' "{\"a\": $(rev a queued "Task A" '{"on_hold":"waiting: second review"}')}" >> "$(log_of "$home")"
  board=$(refresh_board "$home")
  out=$(render "$board" '[{"click":{"attr":"data-task","value":"a"}}]')
  printf '%s' "$out" | jq -e '.error == "" and ([.nodes[] | select(.tag == "img" or .tag == "script")] | length == 0)' >/dev/null     || fail "the on-hold text became markup or broke the page: $out"
  printf '%s' "$out" | jq -e '[.nodes[] | select(.cls == "rb-change") | .text] | any(test("on_hold: <img src=x onerror=alert\\(1\\)> waiting -> waiting: second review"))' >/dev/null \
    || fail "the history did not show the on-hold change as text: $(printf '%s' "$out" | jq -c '[.nodes[] | select(.cls == "rb-change") | .text]')"
  printf '%s' "$out" | jq -e '[.nodes[] | select(.cls == "rb-change") | .text] | any(test("on_hold: \\(empty\\) -> "))' >/dev/null \
    || fail "the history did not show the first marking as a readable change"
  printf '%s' "$out" | jq -e '[.nodes[] | select(.cls == "rb-change") | .text] | map(select(test("[{}\\[\\]\"]"))) | length == 0' >/dev/null \
    || fail "an on-hold history change shows raw JSON"
  pass "the on-hold text is escaped and an on-hold history change reads as plain text"
}

test_a_main_home_card_still_offers_its_reply_terms_and_the_comment_box() {
  local home board out
  home=$(make_home main-card)
  seed_views_log "$home"
  board=$(refresh_board "$home")
  out=$(render "$board" '[{"click":{"attr":"data-task","value":"b"}}]')
  printf '%s' "$out" | jq -e '[.nodes[] | select(.tag == "label") | .text] | index("go") != null and index("later") != null' >/dev/null \
    || fail "the main-home card lost its reply terms"
  printf '%s' "$out" | jq -e '[.nodes[] | select(.tag == "form") | .attrs["data-lavish-question"]] | index("b") != null and index("comment.b") != null' >/dev/null \
    || fail "the main-home card lost its answer form or comment box"
  pass "a main-home card keeps its reply terms, answer form, and comment box"
}

test_merge_and_dispatch_buttons_reuse_the_existing_routes() {
  local home board out
  home=$(make_home task-actions)
  seed_views_log "$home"
  board=$(refresh_board "$home")
  out=$(render "$board" '[{"click":{"attr":"data-task","value":"a"}},{"submit":{"question":"merge.a"}}]')
  printf '%s' "$out" | jq -e '.queued | length == 1 and (.[0] | .question == "merge.a" and .data.selection == "merge")' >/dev/null \
    || fail "the merge button did not queue the merge.<task-id> order: $(printf '%s' "$out" | jq -c .queued)"
  out=$(render "$board" '[{"click":{"attr":"data-task","value":"b"}},{"submit":{"question":"dispatch.charted"}}]')
  printf '%s' "$out" | jq -e '.queued | length == 1 and (.[0] | .question == "dispatch.charted" and .data.selection == "b")' >/dev/null \
    || fail "the dispatch button did not queue dispatch.charted with the task id: $(printf '%s' "$out" | jq -c .queued)"
  out=$(render "$board" '[{"click":{"attr":"data-task","value":"c"}}]')
  printf '%s' "$out" | jq -e '[.nodes[] | select(.tag == "form") | .attrs["data-lavish-question"]] | index("merge.c") == null and index("dispatch.charted") == null' >/dev/null \
    || fail "an in-flight task without a ready PR offered merge or dispatch"
  pass "merge and dispatch buttons send the existing merge.<task-id> and dispatch.charted routes"
}

test_a_comment_queues_with_the_question_markup_and_shows_its_reply() {
  local home board out
  home=$(make_home comment)
  seed_views_log "$home"
  board=$(refresh_board "$home")
  out=$(render "$board" '[{"click":{"attr":"data-task","value":"a"}},{"fill":{"name":"comment","value":"please recheck"}},{"submit":{"question":"comment.a"}}]')
  printf '%s' "$out" | jq -e '.queued | length == 1 and (.[0] | .question == "comment.a" and .tag == "choice"
    and .data.schema == "fm-bearings-comment.v1" and .data.task == "a" and .data.iteration == 3 and .data.text == "please recheck")' >/dev/null \
    || fail "the comment was not queued through the Lavish question markup: $(printf '%s' "$out" | jq -c .queued)"
  pass "a comment queues through the Lavish question markup with its task and iteration"
}

test_a_comment_reply_renders_under_its_comment() {
  local home board out id
  home=$(make_home thread)
  seed_views_log "$home"
  id=$(home_run "$home" "$ROOT/bin/fm-inbox.sh" note --request-id r1 --json '[recap task=a iteration=3] please recheck' | jq -r .id) \
    || fail "could not create the comment note"
  home_run "$home" "$ROOT/bin/fm-inbox.sh" reply "$id" 'rechecked, all good' >/dev/null || fail "could not reply to the note"
  board=$(refresh_board "$home")
  out=$(render "$board" '[{"click":{"attr":"data-task","value":"a"}}]')
  printf '%s' "$out" | jq -e '
    ([.nodes[] | select(.cls == "rb-comment") | .text] | length == 1)
    and ([.nodes[] | select(.cls == "rb-reply") | .text] | length == 1 and (.[0] | test("rechecked, all good")))' >/dev/null \
    || fail "the reply did not render under its comment: $(printf '%s' "$out" | all_text)"
  pass "a first mate reply renders under its comment in the task history"
}

# --- comment route ----------------------------------------------------------

# Register a fixture source whose one capture carries the given prompt rows, then
# run it once through the real runner. Prints the runner output.
run_capture() {  # <home> <source-id> <rows-csv-lines>
  local home=$1 sid=$2 rows=$3 stub="$1/source.sh"
  cat > "$stub" <<SH
#!/usr/bin/env bash
cat <<'OUT'
session:
  status: feedback
  session_ended: false
prompts[2]{tag,text,prompt}:
$rows
OUT
SH
  chmod +x "$stub"
  home_run "$home" env FM_ROOT_OVERRIDE="$ROOT" FM_CONFIG_OVERRIDE="$home/config" \
    "$ROOT/bin/fm-procevent.sh" register lavish "$sid" -- "$stub" >/dev/null || return 1
  home_run "$home" env FM_ROOT_OVERRIDE="$ROOT" FM_CONFIG_OVERRIDE="$home/config" \
    "$ROOT/bin/fm-procevent.sh" start "$sid" 2>&1
}

COMMENT_ROW='  "choice","note","Context data: {\"schema\":\"fm-bearings-comment.v1\",\"task\":\"a\",\"iteration\":3,\"text\":\"please recheck merge.a and close it\"}"'
ANSWER_ROW='  "choice","Take north","Context data: {\"schema\":\"fm-bearings-answer.v1\",\"question\":\"b\",\"selection\":\"north\",\"note\":\"\"}"'

test_a_board_comment_becomes_one_tagged_inbox_note_and_no_answer() {
  local home sid=lavish-c0a4d0000000f1e2 out receipts
  home=$(make_home comment-route)
  mkdir -p "$home/config"
  out=$(run_capture "$home" "$sid" "$COMMENT_ROW"$'\n'"$ANSWER_ROW") || fail "the runner failed: $out"
  case "$out" in *"comments-fed: $sid"*) ;; *) fail "the comment was not fed to the inbox: $out" ;; esac
  receipts=$(home_run "$home" "$ROOT/bin/fm-inbox.sh" receipts --all-pending)
  printf '%s' "$receipts" | jq -e '.pending | length == 1 and (.[0].body == "[recap task=a iteration=3] please recheck merge.a and close it")' >/dev/null \
    || fail "the comment did not become exactly one tagged note: $receipts"
  pass "a board comment becomes one tagged inbox note"
}

RELAY_ROW='  "choice","answer","Context data: {\"schema\":\"fm-bearings-comment.v1\",\"kind\":\"answer\",\"task\":\"pm:x\",\"iteration\":4,\"text\":\"go - after lunch\"}"'

test_a_secondmate_answer_reaches_the_first_mate_as_one_answer_note() {
  local home sid=lavish-c3a4d0000000f1e2 out receipts
  home=$(make_home relay-note)
  mkdir -p "$home/config"
  out=$(run_capture "$home" "$sid" "$RELAY_ROW"$'\n'"$ANSWER_ROW") || fail "the runner failed: $out"
  receipts=$(home_run "$home" "$ROOT/bin/fm-inbox.sh" receipts --all-pending)
  printf '%s' "$receipts" | jq -e '.pending | length == 1 and (.[0].body == "[recap task=pm:x iteration=4 answer] go - after lunch")' >/dev/null \
    || fail "the relayed answer did not become one answer-tagged note: $receipts"
  home_run "$home" "$ROOT/bin/fm-inbox.sh" reply "$(printf '%s' "$receipts" | jq -r '.pending[0].id')" 'relayed to pm' >/dev/null \
    || fail "could not reply to the relayed answer"
  printf '{"schema":"fm-recap-iteration.v1","seq":4,"at":"2026-10-04T09:00:00Z","tasks":["pm:x"],"revisions":{"pm:x":%s},"changed_themes":[],"waiting":1,"warnings":[]}\n' \
    "$(rev pm:x queued "Mate task" '{"held":true,"waiting":true,"reply_terms":["go"]}')" > "$(log_of "$home")"
  home_run "$home" "$PUBLISH" refresh >/dev/null || fail "refresh failed"
  out=$(render "$home/.lavish/bearings-board.html" '[{"click":{"attr":"data-task","value":"pm:x"}}]')
  printf '%s' "$out" | all_text | grep -q 'answer relayed' || fail "the thread did not mark the relayed answer"
  printf '%s' "$out" | all_text | grep -q 'relayed to pm' || fail "the thread did not show the first mate reply"
  pass "a secondmate answer reaches the first mate as one answer-tagged note and shows its reply"
}

test_a_comment_that_names_a_task_never_reaches_the_answer_intake() {
  local home sid=lavish-c1a4d0000000f1e2 out
  home=$(make_home comment-no-answer)
  mkdir -p "$home/config"
  out=$(run_capture "$home" "$sid" "$COMMENT_ROW"$'\n'"$COMMENT_ROW") || fail "the runner failed: $out"
  case "$out" in *"answers-fed"*|*"reconciles-fed"*) fail "a comment reached the keyed-answer intake: $out" ;; esac
  "$home/source.sh" > "$home/captured.txt"
  [ -z "$("$ROOT/bin/fm-procevent-lavish.sh" answers "$home/captured.txt" 2>/dev/null)" ] \
    || fail "the answer parser returned a comment row"
  pass "a comment that names a task id delivers nothing to the answer intake"
}

test_a_repeated_delivery_of_one_capture_replays_the_same_note() {
  local home sid=lavish-c2a4d0000000f1e2 out outcome
  home=$(make_home comment-replay)
  mkdir -p "$home/config"
  out=$(run_capture "$home" "$sid" "$COMMENT_ROW"$'\n'"$ANSWER_ROW") || fail "the runner failed: $out"
  outcome=$(home_run "$home" "$ROOT/bin/fm-inbox.sh" note --request-id "recap-comment:$sid:1:1" --json \
    '[recap task=a iteration=3] please recheck merge.a and close it') || fail "the replayed delivery failed"
  printf '%s' "$outcome" | jq -e '.outcome == "replay"' >/dev/null || fail "the repeat created a second note: $outcome"
  home_run "$home" "$ROOT/bin/fm-inbox.sh" receipts --all-pending | jq -e '.pending | length == 1' >/dev/null \
    || fail "a repeated delivery left more than one pending note"
  pass "a repeated delivery of one capture replays the same inbox note"
}

# --- static page and sibling data file ---------------------------------------

inode_of() { perl -e '@s = stat($ARGV[0]); print "$s[1]\n"' "$1"; }

test_a_data_only_publish_leaves_the_board_page_untouched() {
  local home board before after sum
  home=$(make_home static-page)
  seed_views_log "$home"
  board=$(refresh_board "$home")
  before=$(inode_of "$board")
  sum=$(cksum < "$board")
  entry 4 '["a","b","c"]' "{\"a\": $(rev a "done" "Task A" '{"theme":"LW","summary":"A done"}')}" >> "$(log_of "$home")"
  refresh_board "$home" >/dev/null
  after=$(inode_of "$board")
  [ "$before" = "$after" ] || fail "an ordinary iteration rewrote the board page"
  [ "$sum" = "$(cksum < "$board")" ] || fail "an ordinary iteration changed the board page bytes"
  [ "$(board_payload "$board" | jq .iteration)" = 4 ] || fail "the data file did not carry the new iteration"
  pass "an ordinary iteration rewrites the data file and leaves the board page byte-identical"
}

test_a_changed_template_rewrites_the_board_page_once() {
  local home board tpl before out
  home=$(make_home template-change)
  seed_views_log "$home"
  board=$(refresh_board "$home")
  tpl="$TMP_ROOT/template-change.html"
  { cat "$ROOT/.agents/skills/bearings/assets/recap-board-template.html"; printf '<!-- template v2 -->\n'; } > "$tpl"
  home_run "$home" env FM_RECAP_BOARD_TEMPLATE="$tpl" "$PUBLISH" refresh >/dev/null || fail "refresh with a changed template failed"
  cmp -s "$tpl" "$board" || fail "a changed template did not reach the board page"
  before=$(inode_of "$board")
  home_run "$home" env FM_RECAP_BOARD_TEMPLATE="$tpl" "$PUBLISH" refresh >/dev/null || fail "second refresh failed"
  [ "$before" = "$(inode_of "$board")" ] || fail "an unchanged template was rewritten again"
  out=$(board_payload "$board" | jq -r .schema)
  [ "$out" = fm-recap-board.v1 ] || fail "the data file lost its payload: $out"
  pass "the board page is rewritten when the template changes and only then"
}

test_the_data_file_is_replaced_atomically() {
  local home board dir bad=0 i flag sum reader
  home=$(make_home atomic-data)
  seed_views_log "$home"
  board=$(refresh_board "$home")
  dir=${board%/*}
  flag="$TMP_ROOT/atomic-stop"
  rm -f "$flag" "$TMP_ROOT/atomic-bad"
  (
    while [ ! -e "$flag" ]; do
      board_payload "$board" 2>/dev/null | jq -e '.schema == "fm-recap-board.v1"' >/dev/null 2>&1 \
        || printf 'x\n' >> "$TMP_ROOT/atomic-bad"
    done
  ) &
  reader=$!
  for i in 5 6 7 8; do
    entry "$i" '["a","b","c"]' "{\"a\": $(rev a "done" "Task A" "{\"summary\":\"v$i\"}")}" >> "$(log_of "$home")"
    home_run "$home" "$PUBLISH" refresh >/dev/null || { : > "$flag"; wait "$reader"; fail "refresh failed"; }
  done
  : > "$flag"
  wait "$reader"
  [ ! -e "$TMP_ROOT/atomic-bad" ] || fail "a reader saw a missing or torn data file during a publish"
  [ -z "$(find "$dir" -maxdepth 1 -name '.board.*')" ] || fail "a staging file was left behind"
  sum=$(cksum < "$dir/bearings-board.data.js")
  printf '{"schema":"fm-recap-board.v1"}' > "$TMP_ROOT/bad-recap.json"
  ! home_run "$home" "$ROOT/bin/fm-bearings-board.sh" build "$TMP_ROOT/bad-recap.json" >/dev/null 2>&1 \
    || fail "an invalid payload was accepted"
  [ "$sum" = "$(cksum < "$dir/bearings-board.data.js")" ] || fail "a refused build altered the data file"
  pass "the data file is replaced atomically and a refused build leaves it untouched"
}

# A board at iteration 3 on disk, plus the iteration-4 data file a later publish writes
# at $TMP_ROOT/poll-new-<home name>.js. Prints the board path.
poll_fixture() {  # <home>
  local home=$1 board dir
  seed_views_log "$home"
  board=$(refresh_board "$home")
  dir=${board%/*}
  cp "$dir/bearings-board.data.js" "$TMP_ROOT/poll-old.js"
  entry 4 '["a","b","c"]' "{\"a\": $(rev a "done" "Task A" '{"theme":"LW","summary":"A done"}')}" >> "$(log_of "$home")"
  refresh_board "$home" >/dev/null
  cp "$dir/bearings-board.data.js" "$TMP_ROOT/poll-new-${home##*/}.js"
  cp "$TMP_ROOT/poll-old.js" "$dir/bearings-board.data.js"
  printf '%s\n' "$board"
}

stale_shown() { jq -e '[.nodes[] | select(.attrs.id == "rb-stale") | .hidden] | .[0] == false' >/dev/null; }

test_a_poll_redraws_in_place_keeping_scroll_panel_and_focus() {
  local home board out acts
  home=$(make_home poll-redraw)
  board=$(poll_fixture "$home")
  POLL_NEW="$TMP_ROOT/poll-new-${home##*/}.js"
  acts="[{\"scroll\":240},{\"click\":{\"attr\":\"data-task\",\"value\":\"a\"}},{\"panelscroll\":300},{\"poll\":{\"file\":\"$POLL_NEW\"}}]"
  out=$(render "$board" "$acts")
  printf '%s' "$out" | jq -e '.error == ""' >/dev/null || fail "the poll errored: $out"
  [ "$(printf '%s' "$out" | label_of)" = "Iteration 3 of 4" ] || fail "the poll did not load the new data: $(printf '%s' "$out" | label_of)"
  [ "$(printf '%s' "$out" | badges_of)" = '["Iteration 4 arrived"]' ] || fail "no arrival badge after the poll"
  printf '%s' "$out" | jq -e '[.nodes[] | select(.tag == "h3") | .text] | any(test("Task A$"))' >/dev/null \
    || fail "the poll closed the open task detail"
  printf '%s' "$out" | jq -e '[.nodes[] | select(.attrs.id == "rb-page") | .cls] == ["rb-page rb-page--covered"]' >/dev/null \
    || fail "the poll left the page behind the open panel unclipped"
  [ "$(printf '%s' "$out" | jq '.scrolledTo')" = 240 ] || fail "the poll lost the page scroll"
  printf '%s' "$out" | jq -e '[.nodes[] | select(.cls == "rb-drawer__body") | .scrollTop] == [300]' >/dev/null \
    || fail "the poll lost the panel scroll"
  printf '%s' "$out" | jq -e '.focused.attrs["data-close"] == "1"' >/dev/null || fail "the poll lost focus: $(printf '%s' "$out" | jq -c .focused)"
  printf '%s' "$out" | stale_shown && fail "a good poll showed the stale note"
  out=$(render "$board" "[{\"poll\":{\"file\":\"$TMP_ROOT/poll-old.js\"}}]")
  [ "$(printf '%s' "$out" | jq '.scrolledTo')" = null ] || fail "an unchanged payload redrew the page"
  pass "a poll redraws in place and keeps the page scroll, the open panel and its scroll, and focus, and skips unchanged data"
}

test_a_poll_waits_while_a_field_has_focus_or_unsent_text() {
  local home board out open poll
  home=$(make_home poll-guard)
  board=$(poll_fixture "$home")
  POLL_NEW="$TMP_ROOT/poll-new-${home##*/}.js"
  open='{"click":{"attr":"data-task","value":"a"}}'
  poll="{\"poll\":{\"file\":\"$POLL_NEW\"}}"
  out=$(render "$board" "[$open,{\"fill\":{\"name\":\"comment\",\"value\":\"draft text\"}},$poll,$poll]")
  [ "$(printf '%s' "$out" | label_of)" = "Iteration 3 of 3" ] || fail "a poll redrew over an unsent comment"
  out=$(render "$board" "[$open,{\"focus\":{\"name\":\"comment\"}},$poll]")
  [ "$(printf '%s' "$out" | label_of)" = "Iteration 3 of 3" ] || fail "a poll redrew while a field had focus"
  out=$(render "$board" "[$open,{\"focus\":{\"name\":\"comment\"}},$poll,{\"blur\":true},$poll]")
  [ "$(printf '%s' "$out" | label_of)" = "Iteration 3 of 4" ] || fail "the held update was not applied after focus left"
  out=$(render "$board" "[$open,{\"fill\":{\"name\":\"comment\",\"value\":\"draft text\"}},$poll,{\"submit\":{\"question\":\"comment.a\"}},$poll]")
  [ "$(printf '%s' "$out" | label_of)" = "Iteration 3 of 4" ] || fail "the held update was not applied after the draft was queued"
  printf '%s' "$out" | jq -e '.queued | length == 1' >/dev/null || fail "the draft was not queued before the redraw"
  pass "a poll waits while a field has focus or unsent text and applies the update after"
}

test_a_failed_poll_keeps_the_last_data_and_shows_a_stale_note() {
  local home board out
  home=$(make_home poll-stale)
  board=$(poll_fixture "$home")
  POLL_NEW="$TMP_ROOT/poll-new-${home##*/}.js"
  out=$(render "$board" '[{"poll":{"fail":true}}]')
  printf '%s' "$out" | stale_shown || fail "a failed poll showed no stale note"
  [ "$(printf '%s' "$out" | label_of)" = "Iteration 3 of 3" ] || fail "a failed poll changed the data"
  [ "$(printf '%s' "$out" | jq '.scrolledTo')" = null ] || fail "a failed poll redrew the page"
  out=$(render "$board" "[{\"poll\":{\"fail\":true}},{\"poll\":{\"file\":\"$POLL_NEW\"}}]")
  printf '%s' "$out" | stale_shown && fail "the stale note stayed after a good poll"
  [ "$(printf '%s' "$out" | label_of)" = "Iteration 3 of 4" ] || fail "the poll after a failure did not load the data"
  pass "a failed poll keeps the last data with a stale note that clears on the next good poll"
}

# --- iteration notifications --------------------------------------------------

# A board at iteration 3 on disk and the iteration-4 data file a later publish writes.
# The second argument holds the iteration-4 revisions. Prints the board path.
notify_fixture() {  # <home> <iteration-4 revisions-json>
  local home=$1 board dir
  seed_views_log "$home"
  board=$(refresh_board "$home")
  dir=${board%/*}
  cp "$dir/bearings-board.data.js" "$TMP_ROOT/poll-old.js"
  entry 4 '["a","b","c"]' "$2" >> "$(log_of "$home")"
  refresh_board "$home" >/dev/null
  cp "$dir/bearings-board.data.js" "$TMP_ROOT/poll-new-${home##*/}.js"
  cp "$TMP_ROOT/poll-old.js" "$dir/bearings-board.data.js"
  printf '%s\n' "$board"
}

# Iteration 4: task a finishes (code LW) and task c starts waiting on the reader (code ES).
news_revs() {
  printf '{"a": %s, "c": %s}' \
    "$(rev a done "Task A" '{"theme":"LW","summary":"A done"}')" \
    "$(rev c in_flight "Task C" '{"theme":"ES","summary":"C asks","reply_terms":["go"]}')"
}

NOTIFY_ON='{"notification":"granted","focused":false,"localStorage":{"fm-board-notify":"on"}}'

bell_of() { jq -c '[.nodes[] | select(.cls == "rb-bell")] | .[0] | {text, state: .attrs["data-bell"], disabled}'; }

test_a_new_iteration_notifies_once_naming_the_waiting_and_done_codes() {
  local home board out poll
  home=$(make_home notify-news)
  board=$(notify_fixture "$home" "$(news_revs)")
  poll="{\"poll\":{\"file\":\"$TMP_ROOT/poll-new-${home##*/}.js\"}}"
  out=$(RECAP_HARNESS_ENV=$NOTIFY_ON render "$board" "[$poll,$poll,{\"notifclick\":true}]")
  printf '%s' "$out" | jq -e '.error == ""' >/dev/null || fail "the poll errored: $out"
  printf '%s' "$out" | jq -e '.notifications | length == 1' >/dev/null || fail "not exactly one notification: $(printf '%s' "$out" | jq -c .notifications)"
  [ "$(printf '%s' "$out" | jq -r '.notifications[0].body')" = "Waiting: ES · Done: LW" ] \
    || fail "the notification text is wrong: $(printf '%s' "$out" | jq -c .notifications)"
  [ "$(printf '%s' "$out" | jq '.clicked')" = true ] || fail "a click did not focus the board window"
  [ "$(printf '%s' "$out" | jq '.permissionRequests')" = 0 ] || fail "the page asked for permission without a click"
  pass "a new iteration sends one notification naming the waiting and done codes, and a click focuses the board"
}

test_no_notification_on_first_load_focus_or_progress_only_changes() {
  local home board out new
  home=$(make_home notify-quiet)
  board=$(notify_fixture "$home" "$(news_revs)")
  new="$TMP_ROOT/poll-new-${home##*/}.js"
  out=$(RECAP_HARNESS_ENV=$NOTIFY_ON render "$board")
  printf '%s' "$out" | jq -e '.notifications | length == 0' >/dev/null || fail "the first load notified"
  out=$(RECAP_HARNESS_ENV=$NOTIFY_ON render "$board" "[{\"poll\":{\"file\":\"$TMP_ROOT/poll-old.js\"}}]")
  printf '%s' "$out" | jq -e '.notifications | length == 0' >/dev/null || fail "unchanged data notified"
  out=$(RECAP_HARNESS_ENV='{"notification":"granted","focused":true,"localStorage":{"fm-board-notify":"on"}}' \
    render "$board" "[{\"poll\":{\"file\":\"$new\"}}]")
  printf '%s' "$out" | jq -e '.notifications | length == 0' >/dev/null || fail "a focused tab was notified"
  out=$(RECAP_HARNESS_ENV='{"notification":"granted","focused":false,"localStorage":{}}' \
    render "$board" "[{\"poll\":{\"file\":\"$new\"}}]")
  printf '%s' "$out" | jq -e '.notifications | length == 0' >/dev/null || fail "a bell left off still notified"
  home=$(make_home notify-progress)
  board=$(notify_fixture "$home" "{\"b\": $(rev b in_flight "Task B" '{"theme":"QD","summary":"B moved"}')}")
  out=$(RECAP_HARNESS_ENV=$NOTIFY_ON render "$board" "[{\"poll\":{\"file\":\"$TMP_ROOT/poll-new-${home##*/}.js\"}}]")
  printf '%s' "$out" | jq -e '.error == ""' >/dev/null || fail "the poll errored: $out"
  printf '%s' "$out" | jq -e '.notifications | length == 0' >/dev/null || fail "an in-progress-only change notified"
  pass "no notification on first load, unchanged data, a focused tab, a bell left off, or an in-progress-only change"
}

test_the_bell_asks_permission_only_on_click_and_remembers_the_toggle() {
  local home board out
  home=$(make_home notify-bell)
  board=$(notify_fixture "$home" "$(news_revs)")
  out=$(RECAP_HARNESS_ENV='{"notification":"default"}' render "$board")
  [ "$(printf '%s' "$out" | jq '.permissionRequests')" = 0 ] || fail "the page asked for permission on load"
  [ "$(printf '%s' "$out" | bell_of)" = '{"text":"Notifications off","state":"off","disabled":false}' ] || fail "the idle bell is wrong: $(printf '%s' "$out" | bell_of)"
  out=$(RECAP_HARNESS_ENV='{"notification":"default"}' render "$board" '[{"click":{"attr":"data-bell","value":"off"}}]')
  [ "$(printf '%s' "$out" | jq '.permissionRequests')" = 1 ] || fail "a bell click did not ask for permission once"
  [ "$(printf '%s' "$out" | bell_of)" = '{"text":"Notifications on","state":"on","disabled":false}' ] || fail "the bell is not on after a grant: $(printf '%s' "$out" | bell_of)"
  [ "$(printf '%s' "$out" | jq -r '.local["fm-board-notify"]')" = on ] || fail "the toggle was not remembered"
  out=$(RECAP_HARNESS_ENV='{"notification":"granted","localStorage":{"fm-board-notify":"on"}}' render "$board" '[{"click":{"attr":"data-bell","value":"on"}}]')
  [ "$(printf '%s' "$out" | jq -r '.local["fm-board-notify"]')" = off ] || fail "a second click did not turn the bell off"
  pass "the bell asks for permission only when clicked, and remembers the toggle"
}

test_the_bell_degrades_when_notifications_cannot_work() {
  local home board out
  home=$(make_home notify-degrade)
  board=$(notify_fixture "$home" "$(news_revs)")
  out=$(RECAP_HARNESS_ENV='{"secure":false,"notification":"default"}' render "$board")
  printf '%s' "$out" | jq -e '.error == ""' >/dev/null || fail "an insecure page errored: $out"
  [ "$(printf '%s' "$out" | bell_of)" = '{"text":"notifications need https or localhost","state":"insecure","disabled":true}' ] \
    || fail "the insecure bell is wrong: $(printf '%s' "$out" | bell_of)"
  [ "$(printf '%s' "$out" | jq '.permissionRequests')" = 0 ] || fail "an insecure page asked for permission"
  out=$(RECAP_HARNESS_ENV='{"notification":"absent"}' render "$board")
  [ "$(printf '%s' "$out" | bell_of | jq -r .state)" = unsupported ] || fail "no-Notification bell is wrong"
  out=$(RECAP_HARNESS_ENV='{"notification":"denied"}' render "$board")
  [ "$(printf '%s' "$out" | bell_of | jq -r .state)" = denied ] || fail "denied bell is wrong"
  out=$(RECAP_HARNESS_ENV='{"secure":false,"notification":"absent","focused":false}' \
    render "$board" "[{\"poll\":{\"file\":\"$TMP_ROOT/poll-new-${home##*/}.js\"}}]")
  [ "$(printf '%s' "$out" | jq -r '.error')" = "" ] || fail "polling without Notification broke the page: $out"
  [ "$(printf '%s' "$out" | label_of)" = "Iteration 3 of 4" ] || fail "polling without Notification did not load the data"
  pass "the bell shows the https or localhost limit, unsupported and blocked states, and the page keeps working"
}

# --- ticket and MR links ----------------------------------------------------

LINKS_FIXTURE='[{"kind":"ticket","code":"EXAMPLE-1","url":"https://example.invalid/browse/EXAMPLE-1","text":"Synthetic ticket title"},
  {"kind":"mr","code":"!7001","url":"https://example.invalid/mr/7001","text":"Synthetic MR description"},
  {"kind":"mr","code":"!7002","url":"https://example.invalid/mr/7002"}]'

test_publish_accepts_links_and_stores_them_only_when_present_or_changed() {
  local home
  home=$(make_home links-store)
  write_collect "$home" "[$(collected a queued "Task A"), $(collected b queued "Task B")]"
  write_recap "$home" "{\"a\":{\"links\":$LINKS_FIXTURE}}"
  publish "$home" >/dev/null || fail "a recap with links did not publish"
  tail -1 "$(log_of "$home")" | jq -e '.revisions.a.links | length == 3 and .[0].code == "EXAMPLE-1" and .[1].kind == "mr" and (.[2] | has("text") | not)' >/dev/null \
    || fail "the links were not stored on the revision: $(tail -1 "$(log_of "$home")")"
  tail -1 "$(log_of "$home")" | jq -e '.revisions.b | has("links") | not' >/dev/null \
    || fail "a task without links gained a links field"
  write_recap "$home" '{}'
  publish "$home" >/dev/null || fail "the second publish failed"
  tail -1 "$(log_of "$home")" | jq -e '.revisions == {}' >/dev/null || fail "an unchanged task got a new revision: $(tail -1 "$(log_of "$home")")"
  write_recap "$home" '{"a":{"links":[]}}'
  publish "$home" >/dev/null || fail "an empty links list did not publish"
  tail -1 "$(log_of "$home")" | jq -e '.revisions.a | has("links") | not' >/dev/null || fail "an empty list did not clear the links"
  pass "publish stores links, keeps an unchanged task without a new revision, and an empty list clears them"
}

test_publish_refuses_a_bad_link_entry_and_writes_nothing() {
  local home bad
  home=$(make_home links-invalid)
  write_collect "$home" "[$(collected a queued "Task A")]"
  while IFS= read -r bad; do
    jq -c -n --argjson l "$bad" '{schema: "fm-recap.v1", tasks: {a: {links: $l}}}' > "$home/recap.json"
    publish "$home" >/dev/null 2>&1 && fail "a bad link list published: $bad"
  done <<'JSON'
[{"kind":"epic","code":"EXAMPLE-1","url":"https://example.invalid/a"}]
[{"code":"EXAMPLE-1","url":"https://example.invalid/a"}]
[{"kind":"ticket","url":"https://example.invalid/a"}]
[{"kind":"ticket","code":"","url":"https://example.invalid/a"}]
[{"kind":"ticket","code":"EXAMPLE-1"}]
[{"kind":"ticket","code":"EXAMPLE-1","url":"javascript:alert(1)"}]
[{"kind":"ticket","code":"EXAMPLE-1","url":"ftp://example.invalid/a"}]
[{"kind":"ticket","code":"EXAMPLE-1","url":"https://example.invalid/a b"}]
[{"kind":"mr","code":"!1","url":"https://example.invalid/a","text":7}]
["EXAMPLE-1"]
"EXAMPLE-1"
JSON
  [ ! -e "$(log_of "$home")" ] || fail "a bad link list wrote the log"
  pass "a bad link entry refuses the publish and writes nothing"
}

# --- derived ticket chips -----------------------------------------------------

TICKET_URL_TEMPLATE='https://tracker.example.invalid/browse/{key}'

ticket_home() {  # <name> <config-line-1> [config-line-2]
  local home
  home=$(make_home "$1")
  mkdir -p "$home/config"
  if [ -n "${2-}" ]; then
    printf '%s\n' "$2" > "$home/config/recap-ticket-url"
    [ -z "${3-}" ] || printf '%s\n' "$3" >> "$home/config/recap-ticket-url"
  fi
  printf '%s\n' "$home"
}

last_links() {  # <home> <task-key>
  tail -1 "$(log_of "$1")" | jq -c --arg k "$2" '.revisions[$k].links // null'
}

test_no_ticket_url_config_derives_no_chips() {
  local home
  home=$(ticket_home ticket-none)
  write_collect "$home" "[$(collected a queued "EXAMPLE-12 Task A")]"
  write_recap "$home" '{}'
  publish "$home" >/dev/null || fail "the publish failed"
  [ "$(last_links "$home" a)" = null ] || fail "a chip appeared without the config: $(last_links "$home" a)"
  pass "without config/recap-ticket-url a title key derives no chip"
}

test_a_title_key_with_no_links_gets_a_derived_chip() {
  local home
  home=$(ticket_home ticket-derive "$TICKET_URL_TEMPLATE")
  write_collect "$home" "[$(collected a queued "EXAMPLE-12 Task A"), $(collected b queued "No key here")]"
  write_recap "$home" '{}'
  publish "$home" >/dev/null || fail "the publish failed"
  [ "$(last_links "$home" a)" = '[{"kind":"ticket","code":"EXAMPLE-12","url":"https://tracker.example.invalid/browse/EXAMPLE-12"}]' ] \
    || fail "the derived chip is wrong: $(last_links "$home" a)"
  [ "$(last_links "$home" b)" = null ] || fail "a title without a key got a chip: $(last_links "$home" b)"
  pass "a title key with no links gets a derived ticket chip"
}

test_an_explicit_link_with_the_same_code_is_not_duplicated_and_stays_first() {
  local home
  home=$(ticket_home ticket-same "$TICKET_URL_TEMPLATE")
  write_collect "$home" "[$(collected a queued "EXAMPLE-12 Task A")]"
  write_recap "$home" '{"a":{"links":[{"kind":"ticket","code":"EXAMPLE-12","url":"https://explicit.example.invalid/x","text":"Explicit"}]}}'
  publish "$home" >/dev/null || fail "the publish failed"
  [ "$(last_links "$home" a)" = '[{"kind":"ticket","code":"EXAMPLE-12","url":"https://explicit.example.invalid/x","text":"Explicit"}]' ] \
    || fail "the explicit link was duplicated or replaced: $(last_links "$home" a)"
  pass "an explicit link with the same code is not duplicated and stays first"
}

test_a_different_explicit_link_stays_first_and_the_derived_chip_follows() {
  local home
  home=$(ticket_home ticket-order "$TICKET_URL_TEMPLATE")
  write_collect "$home" "[$(collected a queued "EXAMPLE-12 Task A")]"
  write_recap "$home" '{"a":{"links":[{"kind":"mr","code":"!7001","url":"https://example.invalid/mr/7001"}]}}'
  publish "$home" >/dev/null || fail "the publish failed"
  last_links "$home" a | jq -e 'map(.code) == ["!7001", "EXAMPLE-12"] and .[1].kind == "ticket"' >/dev/null \
    || fail "the order is wrong: $(last_links "$home" a)"
  pass "a different explicit link keeps first position and the derived chip follows"
}

test_two_distinct_title_keys_derive_two_chips_in_title_order() {
  local home
  home=$(ticket_home ticket-two "$TICKET_URL_TEMPLATE")
  write_collect "$home" "[$(collected a queued "EXAMPLE-12 and OTHER-7 then EXAMPLE-12 again")]"
  write_recap "$home" '{}'
  publish "$home" >/dev/null || fail "the publish failed"
  last_links "$home" a | jq -e 'map(.code) == ["EXAMPLE-12", "OTHER-7"] and .[1].url == "https://tracker.example.invalid/browse/OTHER-7"' >/dev/null \
    || fail "two keys did not derive two ordered chips: $(last_links "$home" a)"
  pass "two distinct title keys derive two chips in title order, each once"
}

test_a_custom_key_regex_on_line_two_is_used() {
  local home
  home=$(ticket_home ticket-regex "$TICKET_URL_TEMPLATE" 'ZZ-[0-9]+')
  write_collect "$home" "[$(collected a queued "EXAMPLE-12 and ZZ-3")]"
  write_recap "$home" '{}'
  publish "$home" >/dev/null || fail "the publish failed"
  last_links "$home" a | jq -e 'map(.code) == ["ZZ-3"]' >/dev/null || fail "the custom regex was ignored: $(last_links "$home" a)"
  pass "a regex on line 2 replaces the default key pattern"
}

test_a_bad_template_or_regex_warns_once_and_the_publish_succeeds() {
  local home err cfg n=0
  for cfg in 'https://tracker.example.invalid/browse/' 'ftp://tracker.example.invalid/{key}' 'https://tracker.example.invalid/a b/{key}'; do
    n=$((n + 1))
    home=$(ticket_home "ticket-bad-tpl-$n" "$cfg")
    write_collect "$home" "[$(collected a queued "EXAMPLE-12 Task A")]"
    write_recap "$home" '{}'
    err=$(publish "$home" 2>&1 >/dev/null) || fail "a bad template failed the publish: $cfg"
    [ "$(printf '%s\n' "$err" | grep -c 'ticket chips are not derived')" = 1 ] || fail "expected one warning for $cfg, got: $err"
    [ "$(last_links "$home" a)" = null ] || fail "a bad template still derived a chip: $cfg"
  done
  home=$(ticket_home ticket-bad-re "$TICKET_URL_TEMPLATE" '[unclosed')
  write_collect "$home" "[$(collected a queued "EXAMPLE-12 Task A")]"
  write_recap "$home" '{}'
  err=$(publish "$home" 2>&1 >/dev/null) || fail "a bad regex failed the publish"
  [ "$(printf '%s\n' "$err" | grep -c 'ticket chips are not derived')" = 1 ] || fail "expected one warning for the bad regex, got: $err"
  [ "$(last_links "$home" a)" = null ] || fail "a bad regex still derived a chip"
  pass "a bad template or regex warns once, derives nothing, and the publish succeeds"
}

test_republishing_with_derived_chips_makes_no_new_revision() {
  local home
  home=$(ticket_home ticket-idem "$TICKET_URL_TEMPLATE")
  write_collect "$home" "[$(collected a queued "EXAMPLE-12 Task A")]"
  write_recap "$home" '{"a":{"links":[{"kind":"mr","code":"!7001","url":"https://example.invalid/mr/7001"}]}}'
  publish "$home" >/dev/null || fail "the first publish failed"
  publish "$home" >/dev/null || fail "the second publish failed"
  tail -1 "$(log_of "$home")" | jq -e '.revisions == {}' >/dev/null || fail "a republish made a revision: $(tail -1 "$(log_of "$home")")"
  write_recap "$home" '{}'
  publish "$home" >/dev/null || fail "the third publish failed"
  tail -1 "$(log_of "$home")" | jq -e '.revisions == {}' >/dev/null || fail "a recap without links made a revision: $(tail -1 "$(log_of "$home")")"
  pass "a republish with derived chips makes no new revision"
}

link_anchors() { jq -c '[.nodes[] | select(.tag == "a" and ((.attrs.href // "") | startswith("https://example.invalid/")))]'; }

test_rows_show_link_chips_and_the_panel_shows_a_tickets_and_mrs_section() {
  local home board out
  home=$(make_home links-render)
  entry 1 '["a","b"]' "{
    \"a\": $(rev a queued "Task A" "{\"links\": $LINKS_FIXTURE}"),
    \"b\": $(rev b queued "Task B")}" > "$(log_of "$home")"
  board=$(refresh_board "$home")
  out=$(render "$board")
  printf '%s' "$out" | jq -e '.error == ""' >/dev/null || fail "the board errored: $out"
  printf '%s' "$out" | jq -e '[.nodes[] | select(.cls == "rb-xlink") | .text] == ["EXAMPLE-1", "!7001", "!7002"]' >/dev/null \
    || fail "the row did not carry one chip per link: $(printf '%s' "$out" | jq -c '[.nodes[] | select(.cls == "rb-xlink") | .text]')"
  printf '%s' "$out" | jq -e '[.nodes[] | select(.cls == "rb-xlinks")] | length == 1' >/dev/null \
    || fail "a task without links got a chip strip"
  printf '%s' "$out" | jq -e '[.nodes[] | select(.tag == "h3")] | length == 0' >/dev/null || fail "the panel was open on load"
  printf '%s' "$out" | link_anchors | jq -e 'length == 3 and all(.[]; .attrs.target == "_blank" and .attrs.rel == "noopener noreferrer")' >/dev/null \
    || fail "a chip lacked target or rel: $(printf '%s' "$out" | link_anchors)"
  printf '%s' "$out" | jq -e '[.nodes[] | select(.cls == "fm-badge fm-badge--neutral" or .cls == "fm-badge fm-badge--info") | .text] | all(. != "open" and . != "merged" and . != "closed")' >/dev/null \
    || fail "an MR chip got a state badge"
  # The chip is not part of the row button, so a chip click leaves the panel closed.
  out=$(render "$board" '[{"click":{"text":"EXAMPLE-1"}}]')
  printf '%s' "$out" | jq -e '.error == "" and ([.nodes[] | select(.tag == "h3")] | length == 0)' >/dev/null \
    || fail "a chip click opened the panel or errored: $out"
  printf '%s' "$out" | jq -e '[.nodes[] | select(.cls | test("rb-row$")) | .tag] | all(. == "button")' >/dev/null \
    || fail "a task row stopped being a button"
  out=$(render "$board" '[{"click":{"attr":"data-task","value":"a"}}]')
  printf '%s' "$out" | jq -e '[.nodes[] | select(.tag == "h3") | .text] | index("Tickets & MRs") != null' >/dev/null \
    || fail "the panel has no Tickets & MRs section"
  printf '%s' "$out" | jq -e '[.nodes[] | select(.cls == "rb-row__mark") | .text] | (index("Tickets") != null and index("MRs") != null)' >/dev/null \
    || fail "the panel did not show both groups"
  printf '%s' "$out" | jq -e '[.nodes[] | select(.cls == "rb-xlinkitem") | .text] == ["EXAMPLE-1Synthetic ticket title", "!7001Synthetic MR description", "!7002"]' >/dev/null \
    || fail "the panel items were not code then text: $(printf '%s' "$out" | jq -c '[.nodes[] | select(.cls == "rb-xlinkitem") | .text]')"
  printf '%s' "$out" | link_anchors | jq -e '[.[] | select(.cls == "")] | length == 3 and all(.[]; .attrs.target == "_blank" and .attrs.rel == "noopener noreferrer")' >/dev/null \
    || fail "a panel link lacked target or rel"
  out=$(render "$board" '[{"click":{"attr":"data-task","value":"b"}}]')
  printf '%s' "$out" | jq -e '[.nodes[] | select(.tag == "h3") | .text] | index("Tickets & MRs") == null' >/dev/null \
    || fail "a task without links got the section"
  pass "rows carry linked chips, the panel has a Tickets & MRs section, and a task without links renders as before"
}

test_a_task_with_only_one_link_kind_shows_only_that_group() {
  local home board out
  home=$(make_home links-one-kind)
  entry 1 '["a"]' "{\"a\": $(rev a queued "Task A" '{"links":[{"kind":"mr","code":"!7003","url":"https://example.invalid/mr/7003","text":"Only an MR"}]}')}" > "$(log_of "$home")"
  board=$(refresh_board "$home")
  out=$(render "$board" '[{"click":{"attr":"data-task","value":"a"}}]')
  printf '%s' "$out" | jq -e '[.nodes[] | select(.cls == "rb-row__mark") | .text] | (index("MRs") != null and index("Tickets") == null)' >/dev/null \
    || fail "the panel showed an empty or missing group"
  pass "a panel group is omitted when it has no links"
}

test_link_values_are_escaped_and_an_unsafe_url_never_becomes_a_link() {
  local home board out
  home=$(make_home links-hostile)
  entry 1 '["a"]' "{\"a\": $(rev a queued "Task A" '{"links":[
    {"kind":"ticket","code":"<img src=x onerror=alert(1)>","url":"https://example.invalid/browse/X\"onmouseover=\"alert(1)","text":"<script>alert(2)</script>"},
    {"kind":"ticket","code":"EVIL-1","url":"javascript:alert(3)","text":"bad scheme"},
    {"kind":"mr","code":"EVIL-2","url":"data:text/html,x","text":"bad scheme"},
    {"kind":"epic","code":"EVIL-3","url":"https://example.invalid/e","text":"bad kind"}]}')}" > "$(log_of "$home")"
  board=$(refresh_board "$home")
  out=$(render "$board" '[{"click":{"attr":"data-task","value":"a"}}]')
  printf '%s' "$out" | jq -e '.error == ""' >/dev/null || fail "hostile link values broke the page: $out"
  printf '%s' "$out" | jq -e '[.nodes[] | select(.tag == "img" or .tag == "script")] | length == 0' >/dev/null \
    || fail "a link value became markup"
  printf '%s' "$out" | jq -e '[.nodes[] | select(.cls == "rb-xlink") | .text] == ["<img src=x onerror=alert(1)>"]' >/dev/null \
    || fail "the hostile code was not kept as plain text or an unsafe entry stayed: $(printf '%s' "$out" | jq -c '[.nodes[] | select(.cls == "rb-xlink") | .text]')"
  printf '%s' "$out" | jq -e '[.nodes[] | select(.tag == "a") | .attrs.href // ""] | all(startswith("http://") or startswith("https://") or . == "")' >/dev/null \
    || fail "a non-http link got an href"
  printf '%s' "$out" | jq -e '[.nodes[] | select(.tag == "a" and .attrs.href != null)] | all(.attrs.target == "_blank" and (.attrs.rel | test("noopener")) and (.attrs.rel | test("noreferrer")))' >/dev/null \
    || fail "a link lacked target or rel"
  pass "link values render as plain text and only http(s) urls of a valid kind become links"
}

test_links_appear_after_a_poll_without_losing_scroll_panel_or_focus() {
  local home board dir out acts new="$TMP_ROOT/links-poll-new.js"
  home=$(make_home links-poll)
  seed_views_log "$home"
  board=$(refresh_board "$home")
  dir=${board%/*}
  cp "$dir/bearings-board.data.js" "$TMP_ROOT/links-poll-old.js"
  entry 4 '["a","b","c"]' "{\"a\": $(rev a in_flight "Task A" "{\"theme\":\"LW\",\"summary\":\"A two\",\"links\":$LINKS_FIXTURE}")}" >> "$(log_of "$home")"
  refresh_board "$home" >/dev/null
  cp "$dir/bearings-board.data.js" "$new"
  cp "$TMP_ROOT/links-poll-old.js" "$dir/bearings-board.data.js"
  acts="[{\"scroll\":240},{\"click\":{\"attr\":\"data-task\",\"value\":\"a\"}},{\"panelscroll\":300},{\"poll\":{\"file\":\"$new\"}}]"
  out=$(render "$board" "$acts")
  printf '%s' "$out" | jq -e '.error == ""' >/dev/null || fail "the poll errored: $out"
  [ "$(printf '%s' "$out" | label_of)" = "Iteration 3 of 4" ] || fail "the poll did not load the new data"
  printf '%s' "$out" | jq -e '[.nodes[] | select(.cls == "rb-xlink")] | length == 0' >/dev/null \
    || fail "links showed on an iteration that has none"
  [ "$(printf '%s' "$out" | jq '.scrolledTo')" = 240 ] || fail "the poll lost the page scroll"
  printf '%s' "$out" | jq -e '[.nodes[] | select(.cls == "rb-drawer__body") | .scrollTop] == [300]' >/dev/null || fail "the poll lost the panel scroll"
  printf '%s' "$out" | jq -e '.focused.attrs["data-close"] == "1"' >/dev/null || fail "the poll lost focus"
  # Viewing the new iteration in the same page, with no reload, shows the links in the row and the open panel.
  out=$(render "$board" "[{\"click\":{\"attr\":\"data-task\",\"value\":\"a\"}},{\"poll\":{\"file\":\"$new\"}},{\"click\":{\"attr\":\"data-new-iteration\",\"value\":\"4\"}}]")
  printf '%s' "$out" | jq -e '.error == ""' >/dev/null || fail "the redraw errored: $out"
  printf '%s' "$out" | jq -e '[.nodes[] | select(.cls == "rb-xlink") | .text] == ["EXAMPLE-1", "!7001", "!7002"]' >/dev/null \
    || fail "the chips did not appear after the poll"
  printf '%s' "$out" | jq -e '[.nodes[] | select(.tag == "h3") | .text] | index("Tickets & MRs") != null' >/dev/null \
    || fail "the open panel did not gain the section after the poll"
  pass "links appear after a poll in the row and the open panel, keeping scroll, panel and focus"
}

fm_test_run \
  test_a_board_comment_becomes_one_tagged_inbox_note_and_no_answer \
  test_a_secondmate_answer_reaches_the_first_mate_as_one_answer_note \
  test_a_comment_that_names_a_task_never_reaches_the_answer_intake \
  test_a_repeated_delivery_of_one_capture_replays_the_same_note \
  test_each_publish_appends_one_iteration_with_the_next_sequence_number \
  test_the_real_collection_keys_a_task_by_its_bare_id_and_reads_its_quoted_title \
  test_publish_builds_the_board_while_away_mode_is_active \
  test_a_backlog_change_without_a_publish_creates_no_iteration \
  test_only_changed_tasks_get_a_revision \
  test_a_summary_change_alone_stores_a_revision \
  test_a_revision_stores_every_required_field \
  test_earlier_log_lines_are_never_rewritten \
  test_a_torn_last_line_is_skipped_reported_and_never_rewritten \
  test_the_log_lives_in_gitignored_data \
  test_an_invalid_recap_publishes_nothing \
  test_the_display_window_keeps_the_last_30_iterations_and_every_revision_full \
  test_a_publish_never_asks_lavish_to_open_a_browser_tab \
  test_a_live_session_listed_with_unread_prompts_is_not_reopened \
  test_a_live_update_keeps_the_readers_place_and_badges_the_new_iteration \
  test_the_board_renders_without_session_storage \
  test_the_built_board_opens_in_explore_mode \
  test_the_iteration_view_groups_by_theme_and_marks_each_task \
  test_rows_and_groups_are_ordered_by_priority_emoji \
  test_the_filters_narrow_the_iteration_view \
  test_the_captain_can_move_between_iterations \
  test_a_finished_task_stays_three_iterations_then_hides_but_remains_reachable \
  test_the_task_detail_shows_newest_first_history_with_field_and_note_diffs \
  test_a_task_detail_opens_as_a_panel_over_the_list_without_moving_the_list \
  test_the_panel_closes_with_its_close_button_or_escape_and_keeps_the_list_scroll \
  test_the_open_panel_clips_the_page_behind_it_so_no_text_is_covered \
  test_panel_page_keys_scroll_the_panel_and_leave_editing_keys_to_the_comment_field \
  test_the_panel_header_pins_the_title_and_close_button_and_the_back_link_is_gone \
  test_a_freshly_loaded_board_starts_with_the_panel_closed_and_the_list_rendered \
  test_a_jira_key_links_only_through_the_private_base_setting \
  test_warnings_have_their_own_section_and_never_count_as_work \
  test_a_main_home_hold_queues_its_answer_for_the_captain_hold_intake \
  test_a_secondmate_card_offers_answer_buttons_and_names_who_acts \
  test_a_main_home_card_still_offers_its_reply_terms_and_the_comment_box \
  test_a_blocked_task_shows_a_blocked_badge_and_its_blockers_and_an_unblocked_task_shows_none \
  test_the_detail_state_badge_matches_the_row_tone_and_the_theme_code_reads_as_a_recap_label \
  test_a_secondmate_home_task_with_blockers_shows_the_blocked_badge \
  test_on_hold_is_stored_kept_cleared_and_a_bad_value_publishes_nothing \
  test_an_on_hold_task_shows_an_on_hold_badge_and_its_event_and_an_unmarked_task_shows_none \
  test_a_task_both_blocked_and_on_hold_shows_both_badges \
  test_the_on_hold_text_is_escaped_and_a_history_change_reads_as_text \
  test_merge_and_dispatch_buttons_reuse_the_existing_routes \
  test_a_comment_queues_with_the_question_markup_and_shows_its_reply \
  test_a_comment_reply_renders_under_its_comment \
  test_a_data_only_publish_leaves_the_board_page_untouched \
  test_a_changed_template_rewrites_the_board_page_once \
  test_the_data_file_is_replaced_atomically \
  test_a_poll_redraws_in_place_keeping_scroll_panel_and_focus \
  test_a_poll_waits_while_a_field_has_focus_or_unsent_text \
  test_a_failed_poll_keeps_the_last_data_and_shows_a_stale_note \
  test_a_new_iteration_notifies_once_naming_the_waiting_and_done_codes \
  test_no_notification_on_first_load_focus_or_progress_only_changes \
  test_the_bell_asks_permission_only_on_click_and_remembers_the_toggle \
  test_the_bell_degrades_when_notifications_cannot_work \
  test_publish_accepts_links_and_stores_them_only_when_present_or_changed \
  test_publish_refuses_a_bad_link_entry_and_writes_nothing \
  test_no_ticket_url_config_derives_no_chips \
  test_a_title_key_with_no_links_gets_a_derived_chip \
  test_an_explicit_link_with_the_same_code_is_not_duplicated_and_stays_first \
  test_a_different_explicit_link_stays_first_and_the_derived_chip_follows \
  test_two_distinct_title_keys_derive_two_chips_in_title_order \
  test_a_custom_key_regex_on_line_two_is_used \
  test_a_bad_template_or_regex_warns_once_and_the_publish_succeeds \
  test_republishing_with_derived_chips_makes_no_new_revision \
  test_rows_show_link_chips_and_the_panel_shows_a_tickets_and_mrs_section \
  test_a_task_with_only_one_link_kind_shows_only_that_group \
  test_link_values_are_escaped_and_an_unsafe_url_never_becomes_a_link \
  test_links_appear_after_a_poll_without_losing_scroll_panel_or_focus
