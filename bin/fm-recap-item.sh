#!/usr/bin/env bash
# fm-recap-item.sh - edit one item of an fm-recap.v1 file by its theme, then
# publish the Fleet Recap board.
#
# The first mate updates the live board by changing one item and publishing. This
# command is that one step, so a board update is a single reviewed call instead of
# a hand-written script per edit. The fm-recap.v1 schema is owned by the header of
# bin/fm-recap-publish.sh.
#
# Usage:
#   fm-recap-item.sh <recap.json> <THEME> [--summary <text>] [--emoji <e>]
#                    [--reply-term <t>]... [--add-link kind=..,code=..,url=..[,text=..]]...
#                    [--drop-link <code>]... [--no-publish]
#
# <THEME> selects the one item whose "theme" field equals it, wherever that item
# sits in "tasks". No match or more than one match is an error that names the theme
# and the matching keys, so an edit never lands on a guessed item.
#   --summary, --emoji   Replace the field.
#   --reply-term         Repeatable. Given at least once, it REPLACES the whole
#                        reply_terms list.
#   --add-link           Repeatable. kind is ticket, mr, slack, or doc, code is 1 to
#                        64 characters, url is http(s) without spaces, text is
#                        optional. It replaces an existing link with the same code.
#                        A comma inside url or text is fine, a key name followed by
#                        "=" after a comma starts the next field.
#   --drop-link          Repeatable. Removes the link with that code. A code the
#                        item does not have is an error, because it is almost
#                        always a typo.
#   --no-publish         Write the file and stop.
# At least one edit flag is required. Drops apply before adds, so dropping and
# adding the same code in one call leaves the added link.
#
# The file is rewritten through a temp file in the same directory and a rename, so
# a reader or a crash never sees half a file. Every flag and link is checked
# before the first write.
#
# Unless --no-publish is given, it runs `fm-recap-publish.sh publish <recap.json>`
# in the foreground and prints the iteration, changed, waiting, and url lines. The
# file is already written when publish fails, so a retry is `fm-recap-publish.sh
# publish <recap.json>`.
#
# Exit codes:
#   0  the edit was written and, unless --no-publish, published with an iteration
#   1  no or several matching items, an unknown drop code, an unreadable file,
#      publish failed, or publish printed no "iteration: N" line
#   2  usage error: unknown flag, missing value, bad link spec, or no edit flag
#
# FM_RECAP_PUBLISH_BIN (tests only) replaces the fm-recap-publish.sh path. It
# receives `publish <recap.json>` and `read`, and lets a test run with no board.
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PUBLISH="${FM_RECAP_PUBLISH_BIN:-$SCRIPT_DIR/fm-recap-publish.sh}"
RECAP_SCHEMA=fm-recap.v1

usage() {
  awk '
    NR == 1 { next }
    /^#/ { sub(/^# ?/, ""); print; next }
    { exit }
  ' "$0"
}

fail() {  # <exit-code> <message>
  local code=$1
  shift
  printf 'fm-recap-item: %s\n' "$*" >&2
  exit "$code"
}

# One link spec as a link object, or {err} naming what is wrong. The kind, code,
# and url rules repeat validate_recap in fm-recap-publish.sh on purpose: a link
# that passes here must not make the later publish reject the whole recap.
parse_link() {  # <spec>
  jq -c -n --arg s "$1" '
    [$s | scan("(?:^|,)(kind|code|url|text)=(.*?)(?=,(?:kind|code|url|text)=|$)")] as $p
    | ($p | map(.[0] + "=" + .[1]) | join(",")) as $back
    | ($p | map({key: .[0], value: .[1]}) | from_entries) as $l
    | if $back != $s then {err: "must be kind=..,code=..,url=..[,text=..]"}
      elif ($p | map(.[0]) | unique | length) != ($p | length) then {err: "repeats a field"}
      elif (["ticket", "mr", "slack", "doc"] | index($l.kind)) == null then {err: "kind must be one of ticket, mr, slack, doc"}
      elif (($l.code // "") | length) < 1 or ($l.code | length) > 64 then {err: "code must be 1 to 64 characters"}
      elif ((($l.url // "") | test("^https?://[^\\s]+$")) | not) then {err: "url must be an http or https URL without spaces"}
      else $l end'
}

command -v jq >/dev/null 2>&1 || fail 1 "jq is required"

case "${1-}" in
  -h|--help|help) usage; exit 0 ;;
esac
[ "$#" -ge 2 ] || { usage >&2; exit 2; }
RECAP=$1
THEME=$2
shift 2

PUBLISH_AFTER=1
EDIT='{}'
while [ "$#" -gt 0 ]; do
  flag=$1
  case "$flag" in
    --no-publish) PUBLISH_AFTER=0; shift; continue ;;
    --summary|--emoji|--reply-term|--add-link|--drop-link) ;;
    *) fail 2 "unknown argument: $flag" ;;
  esac
  [ "$#" -ge 2 ] || fail 2 "$flag needs a value"
  value=$2
  shift 2
  case "$flag" in
    --summary) EDIT=$(jq -c --arg v "$value" '. + {summary: $v}' <<< "$EDIT") ;;
    --emoji) EDIT=$(jq -c --arg v "$value" '. + {emoji: $v}' <<< "$EDIT") ;;
    --reply-term)
      [ "${#value}" -ge 1 ] && [ "${#value}" -le 64 ] || fail 2 "--reply-term must be 1 to 64 characters"
      EDIT=$(jq -c --arg v "$value" '.reply_terms += [$v]' <<< "$EDIT") ;;
    --drop-link) EDIT=$(jq -c --arg v "$value" '.drop += [$v]' <<< "$EDIT") ;;
    --add-link)
      link=$(parse_link "$value")
      err=$(jq -r '.err // empty' <<< "$link")
      [ -z "$err" ] || fail 2 "bad --add-link \"$value\": $err"
      EDIT=$(jq -c --argjson l "$link" '.add += [$l]' <<< "$EDIT") ;;
  esac
done
[ "$EDIT" != '{}' ] || fail 2 "no edit flag given, nothing to change"

[ -f "$RECAP" ] || fail 1 "recap data does not exist: $RECAP"
jq -e --arg s "$RECAP_SCHEMA" '.schema == $s and (.tasks | type) == "object"' "$RECAP" >/dev/null 2>&1 \
  || fail 1 "not an $RECAP_SCHEMA file: $RECAP"

keys=$(jq -r --arg t "$THEME" '.tasks | to_entries[]
  | select((.value | type) == "object" and .value.theme == $t) | .key' "$RECAP")
matches=$(printf '%s' "$keys" | awk 'NF { n++ } END { print n + 0 }')
[ "$matches" -ne 0 ] || fail 1 "no item has theme $THEME in $RECAP"
[ "$matches" -eq 1 ] || fail 1 "$matches items have theme $THEME, expected one: $(printf '%s' "$keys" | paste -sd, -)"
KEY=$keys

# The recap file may omit links while the last published revision holds some, and
# publish then keeps those. Starting an add or drop from an empty list would wipe
# them, so seed from the log in that case.
SEED='[]'
if jq -e '.add or .drop' <<< "$EDIT" >/dev/null \
   && ! jq -e --arg k "$KEY" '.tasks[$k] | has("links")' "$RECAP" >/dev/null; then
  SEED=$("$PUBLISH" read | jq -c --arg k "$KEY" \
    '[.[] | .revisions[$k]? | select(. != null)] | (last | .links) // []') \
    || fail 1 "cannot read the iteration log for the current links of $KEY"
fi

missing=$(jq -r --arg k "$KEY" --argjson e "$EDIT" --argjson seed "$SEED" '
  (.tasks[$k].links // $seed | map(.code)) as $have
  | ($e.drop // [])[] | select(. as $c | $have | index($c) | not)' "$RECAP")
[ -z "$missing" ] || fail 1 "item $KEY has no link with code: $(printf '%s' "$missing" | paste -sd, -)"

tmp=$(mktemp "$(dirname "$RECAP")/.$(basename "$RECAP").XXXXXX") || fail 1 "cannot stage the edit"
trap 'rm -f -- "$tmp"' EXIT
# cp -p carries the original mode, which mktemp would otherwise narrow to 0600.
cp -p "$RECAP" "$tmp"
# A task's links is stored as [] rather than removed when the last one is dropped,
# because publish keeps the last revision's links for an omitted field and only an
# explicit empty list clears them.
jq --indent 2 --arg k "$KEY" --argjson e "$EDIT" --argjson seed "$SEED" '
  .tasks[$k] |= (
    . + ($e | del(.add, .drop))
    | if $e.add or $e.drop then
        .links = (
          ((.links // $seed) | map(select(.code as $c | ($e.drop // []) | index($c) | not)))
          | reduce ($e.add // [])[] as $a (.; map(select(.code != $a.code)) + [$a]))
      else . end)' "$RECAP" > "$tmp" || fail 1 "cannot apply the edit to $RECAP"
jq -e --arg s "$RECAP_SCHEMA" '.schema == $s' "$tmp" >/dev/null || fail 1 "the edit produced an invalid recap file"
mv -f -- "$tmp" "$RECAP"
printf 'fm-recap-item: edited %s (theme %s)\n' "$KEY" "$THEME"

[ "$PUBLISH_AFTER" -eq 1 ] || exit 0

status=0
out=$("$PUBLISH" publish "$RECAP" 2>&1) || status=$?
if [ "$status" -ne 0 ]; then
  printf '%s\n' "$out" >&2
  fail 1 "publish failed with exit $status after the file was edited"
fi
printf '%s\n' "$out" | grep -E '^(iteration|changed|waiting|url): ' || true
printf '%s\n' "$out" | grep -qE '^iteration: [0-9]+$' || {
  printf '%s\n' "$out" >&2
  fail 1 "publish printed no \"iteration: N\" line"
}

# publish compares revisions only for tasks that exist in the backlog collection
# and drops any other key without a word, so an edit to such an item reads
# "changed: -". Name the cause here, because the board looks published but shows
# nothing new.
# ponytail: a change to another item of the same theme hides this, check the
# log revision for the key if that ever matters.
changed=$(printf '%s\n' "$out" | sed -n 's/^changed: //p' | tail -1)
if [ -n "$changed" ] && ! printf ',%s,' "$changed" | grep -qF ",$THEME,"; then
  printf 'fm-recap-item: warning: theme %s is not in the changed list (%s). Item key %s may not match a backlog task key, and publish ignores such entries.\n' \
    "$THEME" "$changed" "$KEY" >&2
fi
