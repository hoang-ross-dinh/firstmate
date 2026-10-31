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
      || printf '  %s,open,"http://127.0.0.1:4387/session/0123456789abcdef",0\n' "$(cat "$FM_HOME/lavish-open")"
    ;;
  poll)
    printf 'entered\n' > "$FM_HOME/stub-poll"
    while [ "$SECONDS" -lt "${FM_TEST_STUB_MAX_BLOCK_SECONDS:-120}" ]; do sleep 1; done
    exit 75
    ;;
  *)
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

# Render a built board, optionally driving it with an actions array.
render() {  # <board> [actions-json]
  local board=$1 actions=${2:-} file
  if [ -n "$actions" ]; then
    file=$(mktemp "$TMP_ROOT/actions.XXXXXX")
    printf '%s' "$actions" > "$file"
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

test_the_display_window_keeps_the_last_30_iterations_full_and_older_ones_to_a_line() {
  local home board out i entries=''
  home=$(make_home window)
  for i in $(seq 1 35); do
    entries="$entries$(entry "$i" '["a"]' "{\"a\": $(rev a queued "Task A" "{\"summary\":\"v$i\"}")}")"$'\n'
  done
  printf '%s' "$entries" > "$(log_of "$home")"
  board=$(refresh_board "$home")
  out=$(sed -n '/<script id="bearings-data"/,/<\/script>/p' "$board" | sed '1d;$d')
  printf '%s' "$out" | jq -e '
    (.tasks[0].revisions | length) == 31 and (.tasks[0].older | length) == 4
    and (.tasks[0].older[0].line | test("v4")) and (.iterations | length) == 30' >/dev/null \
    || fail "the board payload did not keep 30 iterations in full and one line per older revision: $(printf '%s' "$out" | jq -c '[(.tasks[0].revisions|length),(.tasks[0].older|length),(.iterations|length)]')"
  [ "$(wc -l < "$(log_of "$home")" | tr -d ' ')" = 35 ] || fail "the display window altered the log"
  pass "the display window shows 30 iterations in full, older revisions as one line, and the log keeps all"
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

test_a_jira_key_renders_as_a_link_with_no_status() {
  local home board out
  home=$(make_home jira)
  {
    entry 1 '["a"]' "{\"a\": $(rev a queued "COD-5987 Task A" '{"note":"see COD-5987"}')}"
  } > "$(log_of "$home")"
  board=$(refresh_board "$home")
  out=$(render "$board" '[{"click":{"attr":"data-task","value":"a"}}]')
  printf '%s' "$out" | jq -e '[.nodes[] | select(.tag == "a") | .attrs.href] == ["https://parcelperform.atlassian.net/browse/COD-5987"]' >/dev/null \
    || fail "the Jira key was not rendered as a single link: $out"
  pass "a Jira key renders as a link only"
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

test_a_secondmate_hold_says_answer_in_chat_and_offers_no_answer_buttons() {
  local home board out
  home=$(make_home chat-answer)
  {
    entry 1 '["pm:x"]' "{\"pm:x\": $(rev pm:x queued "Mate task" '{"held":true,"hold_kind":"captain","waiting":true,"hold_reason":"pick","reply_terms":["go"]}')}"
  } > "$(log_of "$home")"
  board=$(refresh_board "$home")
  out=$(render "$board" '[{"click":{"attr":"data-task","value":"pm:x"}}]')
  printf '%s' "$out" | all_text | grep -q 'answer in chat' || fail "a secondmate hold did not say answer in chat"
  printf '%s' "$out" | jq -e '[.nodes[] | select(.tag == "input" or (.tag == "form" and .attrs["data-lavish-question"] == "x"))] | length == 0' >/dev/null \
    || fail "a secondmate hold offered answer inputs"
  pass "a secondmate hold shows answer in chat and no answer buttons"
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

fm_test_run \
  test_a_board_comment_becomes_one_tagged_inbox_note_and_no_answer \
  test_a_comment_that_names_a_task_never_reaches_the_answer_intake \
  test_a_repeated_delivery_of_one_capture_replays_the_same_note \
  test_each_publish_appends_one_iteration_with_the_next_sequence_number \
  test_the_real_collection_keys_a_task_by_its_bare_id_and_reads_its_quoted_title \
  test_a_backlog_change_without_a_publish_creates_no_iteration \
  test_only_changed_tasks_get_a_revision \
  test_a_summary_change_alone_stores_a_revision \
  test_a_revision_stores_every_required_field \
  test_earlier_log_lines_are_never_rewritten \
  test_a_torn_last_line_is_skipped_reported_and_never_rewritten \
  test_the_log_lives_in_gitignored_data \
  test_an_invalid_recap_publishes_nothing \
  test_the_display_window_keeps_the_last_30_iterations_full_and_older_ones_to_a_line \
  test_the_built_board_opens_in_explore_mode \
  test_the_iteration_view_groups_by_theme_and_marks_each_task \
  test_the_filters_narrow_the_iteration_view \
  test_the_captain_can_move_between_iterations \
  test_a_finished_task_stays_three_iterations_then_hides_but_remains_reachable \
  test_the_task_detail_shows_newest_first_history_with_field_and_note_diffs \
  test_a_jira_key_renders_as_a_link_with_no_status \
  test_warnings_have_their_own_section_and_never_count_as_work \
  test_a_main_home_hold_queues_its_answer_for_the_captain_hold_intake \
  test_a_secondmate_hold_says_answer_in_chat_and_offers_no_answer_buttons \
  test_merge_and_dispatch_buttons_reuse_the_existing_routes \
  test_a_comment_queues_with_the_question_markup_and_shows_its_reply \
  test_a_comment_reply_renders_under_its_comment
