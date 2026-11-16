#!/usr/bin/env bash
# Behavior tests for bin/fm-recap-item.sh: finding an item by theme, the field
# and link edits, the atomic rewrite, and the publish hand-off. Publish is a stub
# through FM_RECAP_PUBLISH_BIN, so no test touches a board, a Lavish session, or
# an iteration log. All data is synthetic.
set -u

# shellcheck source=tests/lib.sh
# shellcheck disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

ITEM="$ROOT/bin/fm-recap-item.sh"
TMP_ROOT=$(fm_test_tmproot fm-recap-item)

command -v jq >/dev/null 2>&1 || { echo "skip: jq not found"; exit 0; }

# The stub records every call, prints $STUB_OUT for publish and $STUB_READ for
# read, and exits with $STUB_EXIT, so one stub covers every publish outcome.
STUB="$TMP_ROOT/stub-publish.sh"
cat > "$STUB" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_LOG"
case "${1-}" in
  read) printf '%s\n' "${STUB_READ:-[]}" ;;
  recap-path) printf '%s\n' "$STUB_RECAP_PATH" ;;
  publish) [ -z "${STUB_OUT-}" ] || printf '%b\n' "$STUB_OUT"; exit "${STUB_EXIT:-0}" ;;
esac
SH
chmod +x "$STUB"

DEFAULT_OUT='iteration: 7\nchanged: LW\nwaiting: 0\nurl: http://127.0.0.1:1/board'

RECAP="$TMP_ROOT/recap.json"
OUT="$TMP_ROOT/out.txt"
ERR="$TMP_ROOT/err.txt"
STUB_LOG="$TMP_ROOT/stub.log"
export STUB_LOG

new_recap() {
  cat > "$RECAP" <<'J'
{
  "schema": "fm-recap.v1",
  "tasks": {
    "alpha": {"summary": "alpha old", "emoji": "A", "theme": "LW", "reply_terms": ["merge", "hold"],
              "links": [{"kind": "ticket", "code": "ABC-1", "url": "https://tracker.example.test/ABC-1"}]},
    "beta": {"summary": "beta old", "theme": "PO", "reply_terms": ["ok"]},
    "gamma": {"summary": "gamma old", "theme": "DP"},
    "side:delta": {"summary": "delta old", "theme": "DP"},
    "bare": {"summary": "no theme"}
  }
}
J
  : > "$STUB_LOG"
}

# Run the command with the stub; set STUB_OUT and STUB_EXIT before the call.
run_item() {
  STATUS=0
  FM_RECAP_PUBLISH_BIN="$STUB" STUB_OUT="${STUB_OUT-$DEFAULT_OUT}" STUB_EXIT="${STUB_EXIT:-0}" \
    "$ITEM" "$RECAP" "$@" > "$OUT" 2> "$ERR" || STATUS=$?
}

# Like run_item but for a call whose first argument is not the recap path.
run_item_default() {
  STATUS=0
  FM_RECAP_PUBLISH_BIN="$STUB" STUB_OUT="${STUB_OUT-$DEFAULT_OUT}" STUB_EXIT="${STUB_EXIT:-0}" \
    "$ITEM" "$@" > "$OUT" 2> "$ERR" || STATUS=$?
}

# The read-back after a publish also logs a `read` call, so count publish calls only.
publish_calls() {
  grep '^publish ' "$STUB_LOG" || true
}

field() {  # <jq-path-under-tasks>
  jq -c ".tasks$1" "$RECAP"
}

test_a_one_match_edit_replaces_summary_and_emoji_and_publishes_once() {
  new_recap
  run_item LW --summary 'alpha new text' --emoji 'Z'
  expect_code 0 "$STATUS" "one-match edit"
  assert_equals '"alpha new text"' "$(field .alpha.summary)" "summary is replaced"
  assert_equals '"Z"' "$(field .alpha.emoji)" "emoji is replaced"
  assert_equals '"beta old"' "$(field .beta.summary)" "another item is untouched"
  assert_equals 'publish '"$RECAP" "$(publish_calls)" "publish ran once on the recap file"
  assert_contains "$(cat "$OUT")" "iteration: 7" "the iteration line is printed"
  assert_contains "$(cat "$OUT")" "url: http://127.0.0.1:1/board" "the other fact lines are printed"
  pass "a one-match edit replaces summary and emoji and publishes once"
}

test_no_match_exits_nonzero_names_the_theme_and_writes_nothing() {
  new_recap
  local before
  before=$(cat "$RECAP")
  run_item NOPE --summary x
  expect_code 1 "$STATUS" "no match"
  assert_contains "$(cat "$ERR")" "NOPE" "the message names the theme"
  assert_equals "$before" "$(cat "$RECAP")" "the file is unchanged"
  assert_equals "" "$(cat "$STUB_LOG")" "publish did not run"
  pass "no match exits non-zero, names the theme, and writes nothing"
}

test_two_matches_exit_nonzero_name_the_theme_and_both_keys() {
  new_recap
  local before
  before=$(cat "$RECAP")
  run_item DP --summary x
  expect_code 1 "$STATUS" "two matches"
  assert_contains "$(cat "$ERR")" "DP" "the message names the theme"
  assert_contains "$(cat "$ERR")" "gamma" "the message names the first key"
  assert_contains "$(cat "$ERR")" "side:delta" "the message names the second key"
  assert_equals "$before" "$(cat "$RECAP")" "the file is unchanged"
  assert_equals "" "$(cat "$STUB_LOG")" "publish did not run"
  pass "two matches exit non-zero and name the theme and both keys"
}

test_reply_terms_given_once_or_more_replace_the_whole_list() {
  new_recap
  run_item LW --reply-term approve --reply-term later
  expect_code 0 "$STATUS" "reply-term replace"
  assert_equals '["approve","later"]' "$(field .alpha.reply_terms)" "the list is replaced, not appended"
  run_item PO --summary only
  assert_equals '["ok"]' "$(field .beta.reply_terms)" "no reply-term flag leaves the list alone"
  pass "reply terms given once or more replace the whole list"
}

test_add_link_accepts_slack_and_doc_and_replaces_a_link_with_the_same_code() {
  new_recap
  run_item LW --no-publish \
    --add-link 'kind=slack,code=THR-1,url=https://chat.example.test/t/1,text=Thread, with comma' \
    --add-link 'kind=doc,code=DOC-1,url=https://docs.example.test/d/1' \
    --add-link 'kind=ticket,code=ABC-1,url=https://tracker.example.test/ABC-1-moved'
  expect_code 0 "$STATUS" "add links"
  assert_equals '["THR-1","DOC-1","ABC-1"]' "$(field '.alpha.links | map(.code)')" "the replaced link moves to the end and no duplicate stays"
  assert_equals '["slack","doc","ticket"]' "$(field '.alpha.links | map(.kind)')" "slack and doc kinds are accepted"
  assert_equals '"https://tracker.example.test/ABC-1-moved"' "$(field '.alpha.links[] | select(.code == "ABC-1") | .url')" "the replaced link has the new url"
  assert_equals '"Thread, with comma"' "$(field '.alpha.links[] | select(.code == "THR-1") | .text')" "a comma inside text is kept"
  pass "add-link accepts slack and doc and replaces a link with the same code"
}

test_add_link_accepts_a_report_path_with_no_url_and_checks_a_given_url() {
  new_recap
  run_item LW --no-publish \
    --add-link 'kind=report,code=data/synthetic-task/report.md' \
    --add-link 'kind=report,code=data/other-task/report.md,url=https://docs.example.test/r/2,text=Findings'
  expect_code 0 "$STATUS" "add report links"
  assert_equals '["ABC-1","data/synthetic-task/report.md","data/other-task/report.md"]' "$(field '.alpha.links | map(.code)')" "both report links are added after the existing link"
  assert_equals 'false' "$(field '.alpha.links[] | select(.code == "data/synthetic-task/report.md") | has("url")')" "a report path is stored with no url"
  run_item LW --no-publish --add-link 'kind=report,code=data/synthetic-task/report.md,url=ftp://docs.example.test/r'
  expect_code 2 "$STATUS" "a report with a non-http url"
  run_item LW --no-publish --add-link 'kind=report,code=,url=https://docs.example.test/r'
  expect_code 2 "$STATUS" "a report with an empty code"
  run_item LW --no-publish --add-link 'kind=ticket,code=X-1'
  expect_code 2 "$STATUS" "a ticket with no url is still refused"
  run_item LW --no-publish --drop-link data/synthetic-task/report.md
  expect_code 0 "$STATUS" "drop a report link by its path"
  assert_equals '["ABC-1","data/other-task/report.md"]' "$(field '.alpha.links | map(.code)')" "the report path is dropped like any other code"
  pass "add-link accepts a report path with no url, checks a given url, and drop-link removes it by path"
}

test_drop_link_removes_by_code_and_an_unknown_code_is_an_error() {
  new_recap
  run_item LW --no-publish --drop-link ABC-1
  expect_code 0 "$STATUS" "drop link"
  assert_equals '[]' "$(field .alpha.links)" "the last link is dropped to an explicit empty list"
  new_recap
  local before
  before=$(cat "$RECAP")
  run_item LW --no-publish --drop-link TYPO-9
  expect_code 1 "$STATUS" "unknown drop code"
  assert_contains "$(cat "$ERR")" "TYPO-9" "the message names the code"
  assert_equals "$before" "$(cat "$RECAP")" "the file is unchanged"
  pass "drop-link removes by code and an unknown code is an error"
}

test_a_bad_link_spec_or_flag_exits_2_before_anything_is_written() {
  new_recap
  local before spec
  before=$(cat "$RECAP")
  for spec in 'kind=ticket,code=X-1' 'kind=jira,code=X-1,url=https://a.example.test/x' \
    'kind=mr,code=,url=https://a.example.test/x' 'kind=mr,code=X-1,url=ftp://a.example.test/x' \
    'kind=mr,code=X-1,url=https://a.example.test/a b' 'kind=mr,kind=doc,code=X-1,url=https://a.example.test/x' \
    'oops,kind=mr,code=X-1,url=https://a.example.test/x'; do
    run_item LW --summary changed --add-link "$spec"
    expect_code 2 "$STATUS" "bad link spec: $spec"
    assert_equals "$before" "$(cat "$RECAP")" "the file is unchanged after: $spec"
  done
  run_item LW --summary changed --bogus
  expect_code 2 "$STATUS" "unknown flag"
  run_item LW --summary
  expect_code 2 "$STATUS" "flag without a value"
  run_item LW
  expect_code 2 "$STATUS" "no edit flag"
  assert_equals "$before" "$(cat "$RECAP")" "the file is unchanged after every refusal"
  assert_equals "" "$(cat "$STUB_LOG")" "publish never ran"
  pass "a bad link spec or flag exits 2 before anything is written"
}

test_the_rewrite_keeps_valid_json_the_mode_and_leaves_no_temp_file() {
  new_recap
  chmod 640 "$RECAP"
  run_item LW --no-publish --summary 'valid after edit'
  expect_code 0 "$STATUS" "edit"
  jq -e '.schema == "fm-recap.v1" and (.tasks | length) == 5' "$RECAP" >/dev/null || fail "the file is not valid fm-recap.v1 JSON"
  assert_equals "640" "$(stat -f %Lp "$RECAP" 2>/dev/null || stat -c %a "$RECAP")" "the mode survives the rewrite"
  assert_equals "recap.json" "$(find "$TMP_ROOT" -maxdepth 1 -name '*recap.json*' -exec basename {} \;)" "no temp file is left beside the recap"
  run_item LW --no-publish --drop-link TYPO-9
  assert_equals "recap.json" "$(find "$TMP_ROOT" -maxdepth 1 -name '*recap.json*' -exec basename {} \;)" "a refused edit leaves no temp file"
  pass "the rewrite keeps valid JSON and the mode and leaves no temp file"
}

test_no_publish_writes_the_file_and_never_calls_publish() {
  new_recap
  run_item LW --no-publish --summary quiet
  expect_code 0 "$STATUS" "no-publish"
  assert_equals '"quiet"' "$(field .alpha.summary)" "the edit is written"
  assert_equals "" "$(cat "$STUB_LOG")" "publish was not called"
  pass "--no-publish writes the file and never calls publish"
}

test_publish_output_without_an_iteration_line_exits_nonzero() {
  new_recap
  STUB_OUT='changed: LW\nurl: x' run_item LW --summary s
  expect_code 1 "$STATUS" "no iteration line"
  assert_contains "$(cat "$ERR")" "iteration" "the message names the missing line"
  new_recap
  STUB_OUT='fm-recap-publish: boom' STUB_EXIT=1 run_item LW --summary s
  expect_code 1 "$STATUS" "failing publish"
  assert_contains "$(cat "$ERR")" "boom" "the publish output is shown"
  assert_equals '"s"' "$(field .alpha.summary)" "the edit stays written when publish fails"
  pass "publish output without an iteration line exits non-zero"
}

test_a_theme_missing_from_the_changed_list_warns_on_stderr() {
  new_recap
  STUB_OUT='iteration: 3\nchanged: -\nwaiting: 0\nurl: u' run_item LW --summary s
  expect_code 0 "$STATUS" "warning case still succeeds"
  assert_contains "$(cat "$ERR")" "warning" "a warning is printed"
  assert_contains "$(cat "$ERR")" "LW" "the warning names the theme"
  assert_contains "$(cat "$ERR")" "alpha" "the warning names the item key"
  new_recap
  STUB_OUT='iteration: 3\nchanged: PO,LW\nwaiting: 0\nurl: u' run_item LW --summary s
  assert_equals "" "$(cat "$ERR")" "no warning when the theme is in the changed list"
  new_recap
  STUB_OUT='iteration: 3\nchanged: LWX\nwaiting: 0\nurl: u' run_item LW --summary s
  assert_contains "$(cat "$ERR")" "warning" "a theme that only prefixes another still warns"
  pass "a theme missing from the changed list warns on stderr"
}

test_link_edits_start_from_the_last_published_links_when_the_file_has_none() {
  new_recap
  local log='[{"revisions":{"beta":{"links":[{"kind":"mr","code":"!5","url":"https://git.example.test/mr/5"}]}}}]'
  STUB_READ=$log run_item PO --no-publish --add-link 'kind=doc,code=D-1,url=https://docs.example.test/1'
  expect_code 0 "$STATUS" "add on a file without links"
  assert_equals '["!5","D-1"]' "$(field '.beta.links | map(.code)')" "the published link is kept beside the new one"
  new_recap
  STUB_READ=$log run_item PO --no-publish --drop-link '!5'
  expect_code 0 "$STATUS" "drop a published link the file lacks"
  assert_equals '[]' "$(field .beta.links)" "the published link is dropped"
  pass "link edits start from the last published links when the file has none"
}

test_key_selects_one_task_when_a_theme_maps_to_several() {
  new_recap
  run_item --key 'side:delta' --summary 'delta new' --no-publish
  expect_code 0 "$STATUS" "edit by key"
  assert_equals '"delta new"' "$(field '["side:delta"].summary')" "the keyed item is edited"
  assert_equals '"gamma old"' "$(field .gamma.summary)" "the other item of the same theme is untouched"
  run_item DP --summary x --no-publish
  expect_code 1 "$STATUS" "ambiguous theme"
  assert_contains "$(cat "$ERR")" "--key" "the message points at --key"
  run_item --key nope --summary x --no-publish
  expect_code 1 "$STATUS" "unknown key"
  assert_contains "$(cat "$ERR")" "nope" "the message names the key"
  run_item LW --key alpha --summary x --no-publish
  expect_code 2 "$STATUS" "theme and key together"
  run_item --summary x --no-publish
  expect_code 2 "$STATUS" "no selector"
  pass "--key selects one task when a theme maps to several"
}

test_a_multi_line_summary_comes_from_stdin_or_a_file() {
  new_recap
  printf 'line one\nline two\n\nline four\n' | FM_RECAP_PUBLISH_BIN="$STUB" "$ITEM" "$RECAP" LW --summary - --no-publish > "$OUT" 2> "$ERR" \
    || fail "summary from stdin was refused: $(cat "$ERR")"
  assert_equals '"line one\nline two\n\nline four"' "$(field .alpha.summary)" "stdin keeps the line breaks"
  printf 'file one\nfile two\n' > "$TMP_ROOT/summary.txt"
  run_item PO --summary-file "$TMP_ROOT/summary.txt" --no-publish
  expect_code 0 "$STATUS" "summary from a file"
  assert_equals '"file one\nfile two"' "$(field .beta.summary)" "the file keeps the line breaks"
  run_item PO --summary-file "$TMP_ROOT/missing.txt" --no-publish
  expect_code 2 "$STATUS" "missing summary file"
  pass "a multi-line summary comes from stdin or a file"
}

test_answer_file_sets_the_item_answer_and_clear_answer_removes_it() {
  new_recap
  printf 'First line\n\n- point one\n- point two\n' > "$TMP_ROOT/answer.md"
  run_item LW --answer-to note-1 --answer-file "$TMP_ROOT/answer.md"
  expect_code 0 "$STATUS" "answer from a file"
  assert_equals '{"to":"note-1","text":"First line\n\n- point one\n- point two"}' "$(field .alpha.answer)" "the answer keeps the line breaks"
  assert_equals '"alpha old"' "$(field .alpha.summary)" "no other field changes"
  assert_equals 'publish '"$RECAP" "$(publish_calls)" "publish ran once"
  run_item LW --clear-answer --no-publish
  expect_code 0 "$STATUS" "clear the answer"
  assert_equals 'false' "$(jq -c '.tasks.alpha | has("answer")' "$RECAP")" "the answer field is removed, not emptied"
  assert_equals '"alpha old"' "$(field .alpha.summary)" "clearing leaves the other fields"
  run_item PO --clear-answer --no-publish
  expect_code 0 "$STATUS" "clearing an item with no answer"
  pass "--answer-file sets the item answer from a file and --clear-answer removes it"
}

test_a_bad_answer_flag_set_exits_2_before_anything_is_written() {
  new_recap
  local before long
  before=$(cat "$RECAP")
  printf 'some answer\n' > "$TMP_ROOT/ok.md"
  printf '  \n\n' > "$TMP_ROOT/blank.md"
  long="$TMP_ROOT/long.md"
  head -c 20001 /dev/zero | tr '\\0' x > "$long"
  run_item LW --answer-file "$TMP_ROOT/ok.md"
  expect_code 2 "$STATUS" "answer file without --answer-to"
  run_item LW --answer-to n1
  expect_code 2 "$STATUS" "--answer-to without an answer file"
  run_item LW --answer-to 'bad id' --answer-file "$TMP_ROOT/ok.md"
  expect_code 2 "$STATUS" "a note id with a space"
  run_item LW --answer-to n1 --answer-file "$TMP_ROOT/missing.md"
  expect_code 2 "$STATUS" "missing answer file"
  run_item LW --answer-to n1 --answer-file "$TMP_ROOT/blank.md"
  expect_code 2 "$STATUS" "blank answer"
  run_item LW --answer-to n1 --answer-file "$long"
  expect_code 2 "$STATUS" "answer over 20000 characters"
  run_item LW --clear-answer --answer-to n1 --answer-file "$TMP_ROOT/ok.md"
  expect_code 2 "$STATUS" "clear together with a new answer"
  assert_equals "$before" "$(cat "$RECAP")" "the file is unchanged after every refusal"
  assert_equals "" "$(cat "$STUB_LOG")" "publish never ran"
  pass "a bad answer flag set exits 2 before anything is written"
}

test_clear_reply_terms_sets_an_empty_list_and_conflicts_with_reply_term() {
  new_recap
  run_item LW --clear-reply-terms --no-publish
  expect_code 0 "$STATUS" "clear"
  assert_equals '[]' "$(field .alpha.reply_terms)" "the list is empty, not absent"
  local before
  before=$(cat "$RECAP")
  run_item LW --clear-reply-terms --reply-term x --no-publish
  expect_code 2 "$STATUS" "clear with a term"
  assert_equals "$before" "$(cat "$RECAP")" "the file is unchanged"
  pass "--clear-reply-terms sets an empty list and conflicts with --reply-term"
}

test_new_creates_an_item_for_a_bare_id_or_a_home_prefixed_key() {
  new_recap
  run_item --new fresh --theme NW --emoji N --summary 'fresh item' --reply-term go --reply-term stop \
    --add-link 'kind=mr,code=!9,url=https://git.example.test/mr/9' --no-publish
  expect_code 0 "$STATUS" "new bare key"
  assert_equals '{"theme":"NW","emoji":"N","summary":"fresh item","reply_terms":["go","stop"],"links":[{"kind":"mr","code":"!9","url":"https://git.example.test/mr/9"}]}' \
    "$(field .fresh)" "the new item holds exactly the given fields"
  run_item --new 'side:omega' --theme NW --no-publish
  expect_code 0 "$STATUS" "new home key"
  assert_equals '{"theme":"NW"}' "$(field '["side:omega"]')" "an item with only a theme is valid"
  assert_equals '"alpha old"' "$(field .alpha.summary)" "the other items are untouched"
  pass "--new creates an item for a bare id or a home-prefixed key"
}

test_new_refuses_an_existing_key_unless_force_replace_and_checks_its_input() {
  new_recap
  local before
  before=$(cat "$RECAP")
  run_item --new alpha --theme NW --summary x --no-publish
  expect_code 1 "$STATUS" "existing key"
  assert_contains "$(cat "$ERR")" "alpha" "the message names the key"
  assert_equals "$before" "$(cat "$RECAP")" "the file is unchanged"
  run_item --new alpha --theme NW --summary 'replaced' --force-replace --no-publish
  expect_code 0 "$STATUS" "force replace"
  assert_equals '{"theme":"NW","summary":"replaced"}' "$(field .alpha)" "the whole entry is replaced, old fields are gone"
  new_recap
  before=$(cat "$RECAP")
  run_item --new 'a:b:c' --theme NW --no-publish
  expect_code 2 "$STATUS" "bad key"
  run_item --new has/slash --theme NW --no-publish
  expect_code 2 "$STATUS" "key with a slash"
  run_item --new ok --summary x --no-publish
  expect_code 2 "$STATUS" "no theme"
  run_item --new ok --theme 'way-too-long-theme-code' --no-publish
  expect_code 2 "$STATUS" "theme over 16 characters"
  run_item --new ok --theme 'bad theme' --no-publish
  expect_code 2 "$STATUS" "theme with a space"
  run_item --new ok --theme NW --drop-link X --no-publish
  expect_code 2 "$STATUS" "drop on a new item"
  run_item --new ok --theme NW --add-link 'kind=jira,code=X,url=https://a.example.test' --no-publish
  expect_code 2 "$STATUS" "bad link on a new item"
  run_item LW --force-replace --summary x --no-publish
  expect_code 2 "$STATUS" "force-replace without --new"
  assert_equals "$before" "$(cat "$RECAP")" "the file is unchanged after every refusal"
  pass "--new refuses an existing key unless --force-replace and checks its input"
}

test_a_new_item_publishes_in_the_same_call() {
  new_recap
  run_item --new fresh --theme NW --summary 'fresh item'
  expect_code 0 "$STATUS" "new and publish"
  assert_equals 'publish '"$RECAP" "$(publish_calls)" "publish ran once on the recap file"
  assert_contains "$(cat "$OUT")" "iteration: 7" "the iteration line is printed"
  assert_contains "$(cat "$OUT")" "changed: LW" "the changed line is printed"
  pass "a new item publishes in the same call"
}

test_the_read_back_names_a_key_that_is_not_a_backlog_task_even_when_the_theme_changed() {
  new_recap
  local entry
  entry='[{"seq":7,"tasks":["beta"],"revisions":{"beta":{"theme":"LW"}}}]'
  STUB_READ=$entry run_item --key alpha --summary s
  expect_code 0 "$STATUS" "warning case still succeeds"
  assert_contains "$(cat "$ERR")" "alpha" "the warning names the key"
  assert_contains "$(cat "$ERR")" "not a task in the backlog" "the warning names the cause"
  entry='[{"seq":7,"tasks":["alpha","beta"],"revisions":{"beta":{"theme":"LW"}}}]'
  STUB_READ=$entry run_item --key alpha --summary s
  assert_contains "$(cat "$ERR")" "no stored field of alpha differs" "a collected task with no change is named"
  entry='[{"seq":7,"tasks":["alpha"],"revisions":{"alpha":{"theme":"LW"}}}]'
  STUB_READ=$entry run_item --key alpha --summary s
  assert_equals "" "$(cat "$ERR")" "no warning when the item has a revision"
  pass "the read-back names a key that is not a backlog task even when the theme changed"
}

# With no path the command asks publish for the default recap file, so the two
# commands never disagree about where the first mate's recap data lives.
test_no_recap_path_uses_the_default_file_that_publish_names() {
  local other="$TMP_ROOT/other.json"
  new_recap
  export STUB_RECAP_PATH="$RECAP"
  run_item_default --key alpha --summary 'edited by key'
  expect_code 0 "$STATUS" "key edit without a path"
  assert_equals '"edited by key"' "$(field .alpha.summary)" "the default file is edited when the call starts with a flag"
  assert_equals 'publish '"$RECAP" "$(publish_calls)" "publish runs on the default file"
  new_recap
  run_item_default LW --summary 'edited by theme'
  expect_code 0 "$STATUS" "theme edit without a path"
  assert_equals '"edited by theme"' "$(field .alpha.summary)" "a first argument that is not a path selects by theme"
  new_recap
  cp "$RECAP" "$other"
  run_item_default "$other" LW --summary 'edited by path'
  expect_code 0 "$STATUS" "edit with an explicit path"
  assert_equals '"edited by path"' "$(jq -c .tasks.alpha.summary "$other")" "an explicit path wins over the default"
  assert_equals '"alpha old"' "$(field .alpha.summary)" "the default file is left alone when a path is given"
  run_item_default recap.json LW --summary 'x'
  assert_contains "$(cat "$ERR")" "recap data does not exist: recap.json" "a bare name ending in .json is a path"
  unset STUB_RECAP_PATH
  pass "no recap path uses the default file that publish names, and an explicit path wins"
}

test_a_missing_default_file_names_the_path_and_the_restore_command() {
  export STUB_RECAP_PATH="$TMP_ROOT/absent-default.json"
  rm -f -- "$STUB_RECAP_PATH"
  run_item_default --new k --theme LW --summary 's'
  expect_code 1 "$STATUS" "missing default file"
  assert_contains "$(cat "$ERR")" "$STUB_RECAP_PATH" "the error names the default path"
  assert_contains "$(cat "$ERR")" "fm-recap-publish.sh restore" "the error names the restore command"
  [ ! -e "$STUB_RECAP_PATH" ] || fail "a refused call created the default file"
  unset STUB_RECAP_PATH
  pass "a missing default file names the path and the restore command"
}

test_against_the_real_publish_the_default_file_is_the_one_publish_reads() {
  local e2e="$TMP_ROOT/e2e-default" out
  mkdir -p "$e2e/home/data" "$e2e/home/config" "$e2e/home/state"
  cp -R "$ROOT/bin" "$e2e/bin"
  printf '#!/usr/bin/env bash\nprintf '"'"'session:\\n  url: "http://127.0.0.1:1/stub"\\n'"'"'\n' > "$e2e/bin/fm-bearings-board.sh"
  chmod +x "$e2e/bin/fm-bearings-board.sh"
  jq -c -n '{tasks: [{id: "t1", key: "t1", home: "main", kind: "task", repo: "r", state: "open", title: "Task one",
    held: false, hold_kind: "", hold_until: "", hold_reason: "", blockers: "", pr_url: "", issue_url: "", note: "", waiting: false}],
    warnings: []}' > "$e2e/home/collect.json"
  jq -c -n '{schema: "fm-recap.v1", tasks: {}}' > "$e2e/home/data/recap.json"
  out=$(FM_HOME="$e2e/home" FM_RECAP_COLLECT_FILE="$e2e/home/collect.json" "$e2e/bin/fm-recap-item.sh" \
    --new t1 --theme LW --summary 'first' 2>&1) || fail "item without a path failed: $out"
  assert_contains "$out" "changed: LW" "the edit of the default file reaches the board"
  assert_equals '"first"' "$(jq -c .tasks.t1.summary "$e2e/home/data/recap.json")" "the home data file holds the edit"
  pass "against the real publish the default file is the one publish reads"
}

# The real publish with only its board build stubbed: this is the contract the
# command depends on, and the reproduction of "changed: -" for an entry whose key
# is not a backlog task.
test_against_the_real_publish_a_non_task_key_is_reported_and_a_task_key_is_not() {
  local e2e="$TMP_ROOT/e2e" out err status=0
  mkdir -p "$e2e/home/data" "$e2e/home/config" "$e2e/home/state"
  cp -R "$ROOT/bin" "$e2e/bin"
  printf '#!/usr/bin/env bash\nprintf '"'"'session:\\n  url: "http://127.0.0.1:1/stub"\\n'"'"'\n' > "$e2e/bin/fm-bearings-board.sh"
  chmod +x "$e2e/bin/fm-bearings-board.sh"
  jq -c -n '{tasks: [{id: "t1", key: "t1", home: "main", kind: "task", repo: "r", state: "open", title: "Task one",
    held: false, hold_kind: "", hold_until: "", hold_reason: "", blockers: "", pr_url: "", issue_url: "", note: "", waiting: false}],
    warnings: []}' > "$e2e/home/collect.json"
  jq -c -n '{schema: "fm-recap.v1", tasks: {}}' > "$e2e/recap.json"
  e2e_item() {
    status=0
    FM_HOME="$e2e/home" FM_RECAP_COLLECT_FILE="$e2e/home/collect.json" "$e2e/bin/fm-recap-item.sh" "$e2e/recap.json" "$@" \
      > "$e2e/out.txt" 2> "$e2e/err.txt" || status=$?
    out=$(cat "$e2e/out.txt")
    err=$(cat "$e2e/err.txt")
  }
  e2e_item --new t1 --theme LW --summary 'first'
  expect_code 0 "$status" "new task item"
  assert_contains "$out" "changed: LW" "a new item for a backlog task is reported as changed"
  assert_equals "" "$err" "no warning for a backlog task"
  e2e_item --key t1 --summary 'a summary-only edit'
  expect_code 0 "$status" "summary-only edit"
  assert_contains "$out" "changed: LW" "a summary-only edit of a backlog task is reported as changed"
  e2e_item --new LW2 --theme LW --summary 'keyed by something that is not a task'
  expect_code 0 "$status" "non-task key"
  assert_contains "$out" "changed: -" "publish drops an entry that is not a backlog task"
  assert_contains "$err" "LW2 is not a task in the backlog" "the command says why"
  pass "against the real publish a non-task key is reported and a task key is not"
}

test_problem_sets_clears_and_reads_stdin_and_a_too_long_one_exits_2() {
  new_recap
  local before long
  run_item LW --problem 'What is wrong, and why it matters.' --no-publish
  expect_code 0 "$STATUS" "problem text"
  assert_equals '"What is wrong, and why it matters."' "$(field .alpha.problem)" "the problem is set"
  STATUS=0
  printf 'from stdin\nsecond line' | FM_RECAP_PUBLISH_BIN="$STUB" "$ITEM" "$RECAP" LW --problem - --no-publish > "$OUT" 2> "$ERR" || STATUS=$?
  expect_code 0 "$STATUS" "problem from stdin"
  assert_equals '"from stdin\nsecond line"' "$(field .alpha.problem)" "stdin keeps its line breaks"
  run_item LW --problem '' --no-publish
  expect_code 0 "$STATUS" "empty problem"
  assert_equals '""' "$(field .alpha.problem)" "an empty text is stored so publish clears the field"
  before=$(cat "$RECAP")
  long=$(printf 'x%.0s' $(seq 1 601))
  run_item LW --problem "$long" --no-publish
  expect_code 2 "$STATUS" "problem over 600 characters"
  assert_equals "$before" "$(cat "$RECAP")" "the file is unchanged"
  pass "--problem sets, reads stdin, clears with an empty text, and refuses over 600 characters"
}

test_option_given_once_or_more_replaces_the_whole_list_and_clear_options_empties_it() {
  new_recap
  run_item LW --option 'term=go-a,means=Fix it, then wait for the deploy.,next=The worker files a ticket.' --option 'term=go-b,means=Skip it.' --no-publish
  expect_code 0 "$STATUS" "two options"
  assert_equals '[{"term":"go-a","means":"Fix it, then wait for the deploy.","next":"The worker files a ticket."},{"term":"go-b","means":"Skip it."}]' \
    "$(field .alpha.options)" "both options are stored, a comma inside a value is kept, and next may be left out"
  assert_equals '["go-a","go-b"]' "$(jq -c '.tasks.alpha.reply_terms' "$RECAP")" "the file's reply terms become the option terms, not the older list"
  run_item LW --option 'term=only,means=The one left.' --no-publish
  assert_equals '[{"term":"only","means":"The one left."}]' "$(field .alpha.options)" "a later call replaces the whole list"
  assert_equals '["only"]' "$(field .alpha.reply_terms)" "and the reply terms with it"
  run_item LW --clear-options --no-publish
  expect_code 0 "$STATUS" "clear options"
  assert_equals '[]' "$(field .alpha.options)" "the list is empty, not absent, so publish clears it"
  assert_equals '[]' "$(field .alpha.reply_terms)" "the reply terms the options made do not come back"
  run_item LW --clear-options --reply-term kept --no-publish
  expect_code 0 "$STATUS" "clear options and name a term"
  assert_equals '["kept"]' "$(field .alpha.reply_terms)" "a term given in the same call stays, whatever the flag order"
  run_item LW --reply-term kept --clear-options --no-publish
  assert_equals '["kept"]' "$(field .alpha.reply_terms)" "also in the other flag order"
  pass "--option replaces the whole list with its terms and --clear-options leaves no options and no stale terms"
}

test_a_bad_option_or_a_conflicting_flag_exits_2_before_anything_is_written() {
  new_recap
  local before spec long65 long301 long201
  before=$(cat "$RECAP")
  long65=$(printf 'x%.0s' $(seq 1 65))
  long301=$(printf 'x%.0s' $(seq 1 301))
  long201=$(printf 'x%.0s' $(seq 1 201))
  for spec in 'means=no term' 'term=t' 'term=,means=m' "term=$long65,means=m" "term=t,means=$long301" \
    "term=t,means=m,next=$long201" 'term=t,means=' 'term=t,term=u,means=m' 'other=x,term=t,means=m' 'plain text'; do
    run_item LW --option "$spec" --no-publish
    expect_code 2 "$STATUS" "bad option spec: $spec"
  done
  run_item LW --option 'term=1,means=m' --option 'term=2,means=m' --option 'term=3,means=m' --option 'term=4,means=m' \
    --option 'term=5,means=m' --option 'term=6,means=m' --option 'term=7,means=m' --no-publish
  expect_code 2 "$STATUS" "seven options"
  run_item LW --option 'term=t,means=m' --reply-term x --no-publish
  expect_code 2 "$STATUS" "--option before --reply-term"
  run_item LW --reply-term x --option 'term=t,means=m' --no-publish
  expect_code 2 "$STATUS" "--reply-term before --option"
  run_item LW --clear-options --option 'term=t,means=m' --no-publish
  expect_code 2 "$STATUS" "--clear-options with --option"
  assert_contains "$(cat "$ERR")" "--clear-options" "the refusal names the flag"
  assert_equals "$before" "$(cat "$RECAP")" "the file is unchanged after every refusal"
  assert_equals "" "$(cat "$STUB_LOG")" "publish never ran"
  pass "a bad option or a conflicting flag exits 2 before anything is written"
}

# The read-back of an ask: iteration 7 holds a revision of alpha that asks, merged with <revision-json>.
asking_read() {  # <revision-json-merged-over-an-ask>
  jq -c -n --argjson rev "$1" '[{seq: 7, tasks: ["alpha"], revisions: {alpha: ({state: "queued", waiting: false, reply_terms: [], options: [{term: "a", means: "m", next: ""}, {term: "b", means: "m", next: ""}]} + $rev)}}]'
}

test_an_ask_that_is_not_held_warns_on_stderr_and_a_held_or_finished_one_does_not() {
  new_recap
  STUB_READ=$(asking_read '{}') run_item --key alpha --summary s
  expect_code 0 "$STATUS" "the warning leaves the exit code alone"
  assert_contains "$(cat "$ERR")" "item alpha asks the captain (2 options) but its backlog task is not held" "an ask that is not held is named with its option count"
  assert_contains "$(cat "$ERR")" "fm-captain-hold.sh" "the warning names the fix"
  STUB_READ=$(jq -c '[(.[0] | .seq = 6), {seq: 7, tasks: ["alpha"], revisions: {}}]' <<< "$(asking_read '{}')") run_item --key alpha --summary s
  assert_contains "$(cat "$ERR")" "asks the captain (2 options)" "an ask stored in an earlier iteration keeps warning"
  STUB_READ=$(asking_read '{"options":[],"reply_terms":["x"]}') run_item --key alpha --summary s
  assert_contains "$(cat "$ERR")" "asks the captain (1 options)" "reply terms alone count as an ask"
  STUB_READ=$(asking_read '{"waiting":true}') run_item --key alpha --summary s
  assert_equals "" "$(cat "$ERR")" "a held ask draws no warning"
  STUB_READ=$(asking_read '{"state":"done"}') run_item --key alpha --summary s
  assert_equals "" "$(cat "$ERR")" "a finished ask draws no warning"
  STUB_READ=$(asking_read '{"options":[],"reply_terms":[]}') run_item --key alpha --summary s
  assert_equals "" "$(cat "$ERR")" "an item that asks nothing draws no warning"
  STUB_READ='[{"seq":7,"tasks":["beta"],"revisions":{"alpha":{"state":"queued","waiting":false,"reply_terms":["x"]}}}]' run_item --key alpha --summary s
  assert_contains "$(cat "$ERR")" "not a task in the backlog" "a key outside the collection keeps its own warning"
  assert_equals "0" "$(grep -c 'asks the captain' "$ERR" || true)" "and draws no ask warning on top of it"
  pass "an ask that is not held warns on stderr and a held, finished, or empty one does not"
}

test_against_the_real_publish_options_derive_the_terms_and_the_warning_stops_once_held() {
  local e2e="$TMP_ROOT/e2e-ask" out err status=0 task
  mkdir -p "$e2e/home/data" "$e2e/home/config" "$e2e/home/state"
  cp -R "$ROOT/bin" "$e2e/bin"
  printf '#!/usr/bin/env bash\nprintf '"'"'session:\\n  url: "http://127.0.0.1:1/stub"\\n'"'"'\n' > "$e2e/bin/fm-bearings-board.sh"
  chmod +x "$e2e/bin/fm-bearings-board.sh"
  write_collect_e2e() {  # <waiting true|false>
    jq -c -n --argjson w "$1" '{tasks: [{id: "t1", key: "t1", home: "main", kind: "task", repo: "r", state: "open", title: "Task one",
      held: $w, hold_kind: (if $w then "captain" else "" end), hold_until: "", hold_reason: "", blockers: "", pr_url: "", issue_url: "", note: "", waiting: $w}],
      warnings: []}' > "$e2e/home/collect.json"
  }
  e2e_item() {
    status=0
    FM_HOME="$e2e/home" FM_RECAP_COLLECT_FILE="$e2e/home/collect.json" "$e2e/bin/fm-recap-item.sh" "$e2e/recap.json" "$@" \
      > "$e2e/out.txt" 2> "$e2e/err.txt" || status=$?
    out=$(cat "$e2e/out.txt")
    err=$(cat "$e2e/err.txt")
  }
  write_collect_e2e false
  jq -c -n '{schema: "fm-recap.v1", tasks: {}}' > "$e2e/recap.json"
  e2e_item --new t1 --theme LW --summary 'first' --reply-term stale
  expect_code 0 "$status" "an item that starts with a bare reply term"
  e2e_item --key t1 --problem 'Synthetic problem.' \
    --option 'term=go-a,means=Do the thing.,next=The worker does it.' --option 'term=go-b,means=Do nothing.'
  expect_code 0 "$status" "the same item given a problem and options"
  assert_contains "$out" "changed: LW" "the options publish as a change"
  assert_contains "$err" "item t1 asks the captain (2 options) but its backlog task is not held" "the real read-back warns while the task is not held"
  task=$(jq -c -s 'last | .revisions.t1 | {problem, reply_terms, terms: [.options[].term]}' "$e2e/home/data/recap-iterations.jsonl")
  assert_equals '{"problem":"Synthetic problem.","reply_terms":["go-a","go-b"],"terms":["go-a","go-b"]}' "$task" "publish stored the problem and derived the reply terms"
  write_collect_e2e true
  e2e_item --key t1 --summary 'second'
  expect_code 0 "$status" "the same item once the task is held"
  assert_equals "" "$err" "no warning once the task is held"
  e2e_item --key t1 --clear-options
  expect_code 0 "$status" "clearing the options"
  task=$(jq -c -s 'last | .revisions.t1 | {has_options: has("options"), reply_terms}' "$e2e/home/data/recap-iterations.jsonl")
  assert_equals '{"has_options":false,"reply_terms":[]}' "$task" "clearing the options leaves neither them nor the older reply term"
  pass "against the real publish options derive the reply terms, the warning stops once held, and clearing them leaves no stale term"
}

fm_test_run \
  test_a_one_match_edit_replaces_summary_and_emoji_and_publishes_once \
  test_no_match_exits_nonzero_names_the_theme_and_writes_nothing \
  test_two_matches_exit_nonzero_name_the_theme_and_both_keys \
  test_reply_terms_given_once_or_more_replace_the_whole_list \
  test_add_link_accepts_slack_and_doc_and_replaces_a_link_with_the_same_code \
  test_add_link_accepts_a_report_path_with_no_url_and_checks_a_given_url \
  test_drop_link_removes_by_code_and_an_unknown_code_is_an_error \
  test_a_bad_link_spec_or_flag_exits_2_before_anything_is_written \
  test_the_rewrite_keeps_valid_json_the_mode_and_leaves_no_temp_file \
  test_no_publish_writes_the_file_and_never_calls_publish \
  test_publish_output_without_an_iteration_line_exits_nonzero \
  test_a_theme_missing_from_the_changed_list_warns_on_stderr \
  test_link_edits_start_from_the_last_published_links_when_the_file_has_none \
  test_key_selects_one_task_when_a_theme_maps_to_several \
  test_a_multi_line_summary_comes_from_stdin_or_a_file \
  test_answer_file_sets_the_item_answer_and_clear_answer_removes_it \
  test_a_bad_answer_flag_set_exits_2_before_anything_is_written \
  test_clear_reply_terms_sets_an_empty_list_and_conflicts_with_reply_term \
  test_new_creates_an_item_for_a_bare_id_or_a_home_prefixed_key \
  test_new_refuses_an_existing_key_unless_force_replace_and_checks_its_input \
  test_a_new_item_publishes_in_the_same_call \
  test_the_read_back_names_a_key_that_is_not_a_backlog_task_even_when_the_theme_changed \
  test_no_recap_path_uses_the_default_file_that_publish_names \
  test_a_missing_default_file_names_the_path_and_the_restore_command \
  test_against_the_real_publish_the_default_file_is_the_one_publish_reads \
  test_against_the_real_publish_a_non_task_key_is_reported_and_a_task_key_is_not \
  test_problem_sets_clears_and_reads_stdin_and_a_too_long_one_exits_2 \
  test_option_given_once_or_more_replaces_the_whole_list_and_clear_options_empties_it \
  test_a_bad_option_or_a_conflicting_flag_exits_2_before_anything_is_written \
  test_an_ask_that_is_not_held_warns_on_stderr_and_a_held_or_finished_one_does_not \
  test_against_the_real_publish_options_derive_the_terms_and_the_warning_stops_once_held
