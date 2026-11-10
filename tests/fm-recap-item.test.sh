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
  assert_equals 'publish '"$RECAP" "$(cat "$STUB_LOG")" "publish ran once on the recap file"
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

fm_test_run \
  test_a_one_match_edit_replaces_summary_and_emoji_and_publishes_once \
  test_no_match_exits_nonzero_names_the_theme_and_writes_nothing \
  test_two_matches_exit_nonzero_name_the_theme_and_both_keys \
  test_reply_terms_given_once_or_more_replace_the_whole_list \
  test_add_link_accepts_slack_and_doc_and_replaces_a_link_with_the_same_code \
  test_drop_link_removes_by_code_and_an_unknown_code_is_an_error \
  test_a_bad_link_spec_or_flag_exits_2_before_anything_is_written \
  test_the_rewrite_keeps_valid_json_the_mode_and_leaves_no_temp_file \
  test_no_publish_writes_the_file_and_never_calls_publish \
  test_publish_output_without_an_iteration_line_exits_nonzero \
  test_a_theme_missing_from_the_changed_list_warns_on_stderr \
  test_link_edits_start_from_the_last_published_links_when_the_file_has_none
