#!/usr/bin/env bash
# fm-recap-item.sh - edit or create one item of an fm-recap.v1 file, then publish
# the Fleet Recap board.
#
# The first mate updates the live board by changing one item and publishing. This
# command is that one step, so a board update is a single reviewed call instead of
# a hand-written script per edit. The fm-recap.v1 schema is owned by the header of
# bin/fm-recap-publish.sh.
#
# Usage:
#   fm-recap-item.sh [<recap.json>] <THEME>      [edit flags]
#   fm-recap-item.sh [<recap.json>] --key <key>  [edit flags]
#   fm-recap-item.sh [<recap.json>] --new <key> --theme <T> [item flags]
#
# The recap file. A first argument that holds a slash or ends in ".json" is the
# recap path and wins. Any other first argument is not a path, so the command uses
# the default recap file, the one `fm-recap-publish.sh recap-path` prints
# ($DATA/recap.json in the firstmate home). The default file must exist already:
# `fm-recap-publish.sh restore` rebuilds it from the iteration log.
#
# Selecting the item. Give exactly one of:
#   <THEME>        The one item whose "theme" field equals it. No match or several
#                  matches is an error that names the theme and the matching keys,
#                  so an edit never lands on a guessed item. A theme can map to
#                  several tasks, and then --key is the way to name one.
#   --key <key>    The item with that task key: the bare task id for the main home,
#                  or "<home>:<id>" for a second-mate home. No such item is an error.
#   --new <key>    Create the item under that key. The key must be a bare task id
#                  or "<home>:<id>" made of letters, digits, dots, dashes, and
#                  underscores. --theme is required. An existing key is an error
#                  unless --force-replace is given, which replaces the whole entry.
#
# Edit flags (each is optional, at least one is required for <THEME> and --key):
#   --theme <T>          Replace the theme (1 to 16 letters, digits, dots, dashes,
#                        underscores).
#   --summary <text>     Replace the summary. "-" reads the summary from stdin.
#   --summary-file <p>   Replace the summary with the contents of a file. Both forms
#                        keep line breaks, so a multi-line summary is one call.
#   --emoji <e>          Replace the emoji.
#   --reply-term <t>     Repeatable. Given at least once, it REPLACES the whole
#                        reply_terms list. Each term is 1 to 64 characters.
#   --clear-reply-terms  Set reply_terms to []. It cannot be combined with
#                        --reply-term.
#   --problem <text>     Replace the problem: what is wrong or asked, and why it
#                        matters, at most 600 characters. "-" reads it from stdin
#                        and an empty text clears it.
#   --option term=..,means=..[,next=..]
#                        Repeatable. Given at least once, it REPLACES the whole
#                        options list with 1 to 6 options. term is 1 to 64
#                        characters and is the exact reply term, means is what the
#                        option does and costs (at most 300 characters), next is
#                        what happens after the answer (at most 200). It also sets
#                        reply_terms to the option terms, so --option cannot be
#                        combined with --reply-term. A comma inside a value is
#                        fine, a key name followed by "=" after a comma starts
#                        the next field.
#   --clear-options      Set options to [] and reply_terms to [], unless the same
#                        call gives --reply-term. It cannot be combined with
#                        --option.
#   --add-link kind=..,code=..,url=..[,text=..]
#                        Repeatable. kind is ticket, mr, slack, doc, or report, code
#                        is 1 to 64 characters, url is http(s) without spaces, text
#                        is optional. A report is a file path that has no page, so
#                        its code is the path and its url may be left out. It replaces an existing link with the same code.
#                        A comma inside url or text is fine, a key name followed by
#                        "=" after a comma starts the next field.
#   --drop-link <code>   Repeatable. Removes the link with that code. A code the
#                        item does not have is an error, because it is almost
#                        always a typo. Not valid with --new.
#   --answer-to <id>     The comment note id the answer responds to, 1 to 64
#                        characters of letters, digits, dots, dashes, underscores.
#                        Required with --answer-file, the same id fm-inbox.sh reply
#                        takes.
#   --answer-file <p>    Set the item's answer to the Markdown in a file, with
#                        --answer-to. It keeps line breaks. The text must not be
#                        blank and is at most 20000 characters.
#   --clear-answer       Remove the item's answer from the file. It cannot be
#                        combined with --answer-file. Publish sends whatever answer
#                        the file holds, so clear it once the answer is published.
#                        An answer already stored stays in the log and History.
#   --force-replace      Only with --new.
#   --no-publish         Write the file and stop.
# Drops apply before adds, so dropping and adding the same code in one call leaves
# the added link.
#
# The file is rewritten through a temp file in the same directory and a rename, so
# a reader or a crash never sees half a file. Every flag, key, and link is checked
# before the first write, and nothing is published after a refusal.
#
# Unless --no-publish is given, it runs `fm-recap-publish.sh publish <recap.json>`
# in the foreground and prints the iteration, changed, waiting, and url lines. The
# file is already written when publish fails, so a retry is `fm-recap-publish.sh
# publish <recap.json>`.
#
# THE WARNINGS. publish builds revisions only for entries keyed by a task in the
# backlog collection and drops any other key without a word, so such an edit reads
# "changed: -" and the board shows nothing new. After a publish this command reads
# the new iteration back and warns on stderr, still exiting 0, when the item's key
# is not a collected task, or when no stored field of the item changed. When the
# iteration cannot be read back it falls back to warning that the item's theme is
# missing from the changed list. It also warns, on the last stored revision of an
# open item, when the item asks the captain (it holds options or reply terms) but
# its backlog task is not held, because then no hold records the call.
#
# Exit codes:
#   0  the edit was written and, unless --no-publish, published with an iteration
#   1  no, several, or an existing matching item, an unknown drop code, an
#      unreadable file, publish failed, or publish printed no "iteration: N" line
#   2  usage error: unknown flag, missing value, bad link spec, bad option spec,
#      bad key or theme, a conflicting flag pair, a bad or half-given answer, or
#      no selector or edit flag
#
# FM_RECAP_PUBLISH_BIN (tests only) replaces the fm-recap-publish.sh path. It
# receives `publish <recap.json>` and `read`, and lets a test run with no board.
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PUBLISH="${FM_RECAP_PUBLISH_BIN:-$SCRIPT_DIR/fm-recap-publish.sh}"
RECAP_SCHEMA=fm-recap.v1
LINK_KEY_RE='^[A-Za-z0-9._-]+(:[A-Za-z0-9._-]+)?$'
THEME_RE='^[A-Za-z0-9._-]{1,16}$'

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

# jq counts characters and bash under a C locale counts bytes, so a length limit
# is measured by jq to agree with validate_recap in fm-recap-publish.sh.
chars() {  # <text>
  jq -n --arg v "$1" '$v | length'
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
      elif (["ticket", "mr", "slack", "doc", "report"] | index($l.kind)) == null then {err: "kind must be one of ticket, mr, slack, doc, report"}
      elif (($l.code // "") | length) < 1 or ($l.code | length) > 64 then {err: "code must be 1 to 64 characters"}
      elif ($l.kind == "report" and ($l | has("url") | not)) then $l
      elif ((($l.url // "") | test("^https?://[^\\s]+$")) | not) then {err: "url must be an http or https URL without spaces"}
      else $l end'
}

# One option spec as an option object, or {err} naming what is wrong. The limits
# repeat validate_recap in fm-recap-publish.sh on purpose: an option that passes
# here must not make the later publish reject the whole recap. means is required
# here, though publish accepts an option without one, because an option the
# captain cannot read the meaning of is what the board flags.
parse_option() {  # <spec>
  jq -c -n --arg s "$1" '
    [$s | scan("(?:^|,)(term|means|next)=(.*?)(?=,(?:term|means|next)=|$)")] as $p
    | ($p | map(.[0] + "=" + .[1]) | join(",")) as $back
    | ($p | map({key: .[0], value: .[1]}) | from_entries) as $o
    | if $back != $s then {err: "must be term=..,means=..[,next=..]"}
      elif ($p | map(.[0]) | unique | length) != ($p | length) then {err: "repeats a field"}
      elif (($o.term // "") | length) < 1 or ($o.term | length) > 64 then {err: "term must be 1 to 64 characters"}
      elif (($o.means // "") | length) < 1 or ($o.means | length) > 300 then {err: "means must be 1 to 300 characters"}
      elif ($o | has("next")) and ($o.next | length) > 200 then {err: "next must be 200 characters or fewer"}
      else $o end'
}

command -v jq >/dev/null 2>&1 || fail 1 "jq is required"

case "${1-}" in
  -h|--help|help) usage; exit 0 ;;
esac
[ "$#" -ge 1 ] || { usage >&2; exit 2; }
# Publish owns the default path so the two commands cannot disagree on it. It is
# asked only when no path was given, so an explicit call never depends on it.
DEFAULT_RECAP=0
case "$1" in
  */*|*.json) RECAP=$1; shift ;;
  *)
    RECAP=$("$PUBLISH" recap-path) || fail 1 "cannot get the default recap path from publish"
    DEFAULT_RECAP=1 ;;
esac
[ "$#" -ge 1 ] || { usage >&2; exit 2; }

SEL_THEME=''
SEL_KEY=''
NEW_KEY=''
PUBLISH_AFTER=1
FORCE_REPLACE=0
CLEAR_TERMS=0
ADD_TERMS=0
CLEAR_OPTIONS=0
ADD_OPTIONS=0
CLEAR_ANSWER=0
ANSWER_TO=''
ANSWER_TEXT=''
HAVE_ANSWER=0
EDIT='{}'

# The theme selector is positional so the common call stays short. A leading "-"
# is a flag, which keeps a missing theme from being read as one.
case "$1" in
  -*) ;;
  *) SEL_THEME=$1; shift ;;
esac

while [ "$#" -gt 0 ]; do
  flag=$1
  case "$flag" in
    --no-publish) PUBLISH_AFTER=0; shift; continue ;;
    --force-replace) FORCE_REPLACE=1; shift; continue ;;
    --clear-reply-terms)
      CLEAR_TERMS=1
      EDIT=$(jq -c '. + {reply_terms: []}' <<< "$EDIT")
      shift; continue ;;
    --clear-options)
      CLEAR_OPTIONS=1
      EDIT=$(jq -c '. + {options: []}' <<< "$EDIT")
      shift; continue ;;
    --clear-answer)
      CLEAR_ANSWER=1
      shift; continue ;;
    --key|--new|--theme|--summary|--summary-file|--problem|--option|--answer-to|--answer-file|--emoji|--reply-term|--add-link|--drop-link) ;;
    *) fail 2 "unknown argument: $flag" ;;
  esac
  [ "$#" -ge 2 ] || fail 2 "$flag needs a value"
  value=$2
  shift 2
  case "$flag" in
    --key)
      [ -z "$SEL_KEY" ] || fail 2 "--key was given twice"
      SEL_KEY=$value ;;
    --new)
      [ -z "$NEW_KEY" ] || fail 2 "--new was given twice"
      printf '%s' "$value" | grep -qE "$LINK_KEY_RE" \
        || fail 2 "--new key \"$value\" must be a task id or <home>:<id> of letters, digits, dots, dashes, and underscores"
      NEW_KEY=$value ;;
    --theme)
      printf '%s' "$value" | grep -qE "$THEME_RE" \
        || fail 2 "--theme must be 1 to 16 letters, digits, dots, dashes, or underscores"
      EDIT=$(jq -c --arg v "$value" '. + {theme: $v}' <<< "$EDIT") ;;
    --summary)
      # A lone "-" means stdin, the usual convention, so a long summary needs no
      # shell quoting.
      [ "$value" != "-" ] || value=$(cat)
      EDIT=$(jq -c --arg v "$value" '. + {summary: $v}' <<< "$EDIT") ;;
    --summary-file)
      [ -f "$value" ] || fail 2 "--summary-file does not exist: $value"
      value=$(cat -- "$value")
      EDIT=$(jq -c --arg v "$value" '. + {summary: $v}' <<< "$EDIT") ;;
    --problem)
      [ "$value" != "-" ] || value=$(cat)
      [ "$(chars "$value")" -le 600 ] || fail 2 "--problem must be 600 characters or fewer"
      EDIT=$(jq -c --arg v "$value" '. + {problem: $v}' <<< "$EDIT") ;;
    --option)
      option=$(parse_option "$value")
      err=$(jq -r '.err // empty' <<< "$option")
      [ -z "$err" ] || fail 2 "bad --option \"$value\": $err"
      ADD_OPTIONS=$((ADD_OPTIONS + 1))
      [ "$ADD_OPTIONS" -le 6 ] || fail 2 "--option was given more than 6 times"
      EDIT=$(jq -c --argjson o "$option" '.options += [$o]' <<< "$EDIT") ;;
    --answer-to)
      printf '%s' "$value" | grep -qE '^[A-Za-z0-9._-]{1,64}$' \
        || fail 2 "--answer-to must be 1 to 64 letters, digits, dots, dashes, or underscores"
      ANSWER_TO=$value ;;
    --answer-file)
      [ -f "$value" ] || fail 2 "--answer-file does not exist: $value"
      ANSWER_TEXT=$(cat -- "$value")
      HAVE_ANSWER=1 ;;
    --emoji) EDIT=$(jq -c --arg v "$value" '. + {emoji: $v}' <<< "$EDIT") ;;
    --reply-term)
      [ "$(chars "$value")" -ge 1 ] && [ "$(chars "$value")" -le 64 ] || fail 2 "--reply-term must be 1 to 64 characters"
      ADD_TERMS=1
      EDIT=$(jq -c --arg v "$value" '.reply_terms += [$v]' <<< "$EDIT") ;;
    --drop-link) EDIT=$(jq -c --arg v "$value" '.drop += [$v]' <<< "$EDIT") ;;
    --add-link)
      link=$(parse_link "$value")
      err=$(jq -r '.err // empty' <<< "$link")
      [ -z "$err" ] || fail 2 "bad --add-link \"$value\": $err"
      EDIT=$(jq -c --argjson l "$link" '.add += [$l]' <<< "$EDIT") ;;
  esac
done

selectors=0
for s in "$SEL_THEME" "$SEL_KEY" "$NEW_KEY"; do
  [ -z "$s" ] || selectors=$((selectors + 1))
done
[ "$selectors" -eq 1 ] || fail 2 "give exactly one of <THEME>, --key, or --new"
[ "$CLEAR_TERMS$ADD_TERMS" != 11 ] || fail 2 "--clear-reply-terms cannot be combined with --reply-term"
[ "$CLEAR_OPTIONS" -eq 0 ] || [ "$ADD_OPTIONS" -eq 0 ] || fail 2 "--clear-options cannot be combined with --option"
# The publish writes reply_terms from options, so a hand-set term list beside them
# would be silently overridden, and the two flags are refused instead.
[ "$ADD_OPTIONS" -eq 0 ] || [ "$ADD_TERMS" -eq 0 ] || fail 2 "--option cannot be combined with --reply-term"
# The file keeps reply_terms equal to the option terms. Publish ignores reply_terms
# while options exist, so an older list left beside the options would come back
# the moment the options are cleared. Both are built here, after the loop, so the
# order of the flags does not matter.
if [ "$ADD_OPTIONS" -gt 0 ]; then
  EDIT=$(jq -c '. + {reply_terms: (.options | map(.term))}' <<< "$EDIT")
elif [ "$CLEAR_OPTIONS" -eq 1 ] && [ "$ADD_TERMS" -eq 0 ]; then
  EDIT=$(jq -c '. + {reply_terms: []}' <<< "$EDIT")
fi
# The answer limits repeat validate_recap in fm-recap-publish.sh on purpose: an
# answer that passes here must not make the later publish reject the whole recap.
# The answer is built after the loop because its two flags arrive in either order.
[ "$CLEAR_ANSWER$HAVE_ANSWER" != 11 ] || fail 2 "--clear-answer cannot be combined with --answer-file"
[ "$HAVE_ANSWER" -eq 1 ] || [ -z "$ANSWER_TO" ] || fail 2 "--answer-to needs --answer-file"
if [ "$HAVE_ANSWER" -eq 1 ]; then
  [ -n "$ANSWER_TO" ] || fail 2 "--answer-file needs --answer-to"
  printf '%s' "$ANSWER_TEXT" | grep -q '[^[:space:]]' || fail 2 "--answer-file is blank"
  [ "$(chars "$ANSWER_TEXT")" -le 20000 ] || fail 2 "--answer-file is longer than 20000 characters"
  EDIT=$(jq -c --arg to "$ANSWER_TO" --arg t "$ANSWER_TEXT" '. + {answer: {to: $to, text: $t}}' <<< "$EDIT")
fi
[ "$CLEAR_ANSWER" -eq 0 ] || EDIT=$(jq -c '. + {clear_answer: true}' <<< "$EDIT")
if [ -n "$NEW_KEY" ]; then
  jq -e 'has("theme")' <<< "$EDIT" >/dev/null || fail 2 "--new needs --theme"
  ! jq -e 'has("drop")' <<< "$EDIT" >/dev/null || fail 2 "--drop-link is not valid with --new"
else
  [ "$FORCE_REPLACE" -eq 0 ] || fail 2 "--force-replace is only valid with --new"
  [ "$EDIT" != '{}' ] || fail 2 "no edit flag given, nothing to change"
fi

if [ ! -f "$RECAP" ]; then
  [ "$DEFAULT_RECAP" -eq 0 ] || fail 1 "recap data does not exist: $RECAP (rebuild it from the log with: fm-recap-publish.sh restore)"
  fail 1 "recap data does not exist: $RECAP"
fi
jq -e --arg s "$RECAP_SCHEMA" '.schema == $s and (.tasks | type) == "object"' "$RECAP" >/dev/null 2>&1 \
  || fail 1 "not an $RECAP_SCHEMA file: $RECAP"

IS_NEW=0
if [ -n "$NEW_KEY" ]; then
  IS_NEW=1
  KEY=$NEW_KEY
  if jq -e --arg k "$KEY" '.tasks | has($k)' "$RECAP" >/dev/null && [ "$FORCE_REPLACE" -eq 0 ]; then
    fail 1 "item $KEY already exists, use --force-replace to replace it"
  fi
elif [ -n "$SEL_KEY" ]; then
  KEY=$SEL_KEY
  jq -e --arg k "$KEY" '.tasks[$k] | type == "object"' "$RECAP" >/dev/null 2>&1 \
    || fail 1 "no item has key $KEY in $RECAP"
else
  keys=$(jq -r --arg t "$SEL_THEME" '.tasks | to_entries[]
    | select((.value | type) == "object" and .value.theme == $t) | .key' "$RECAP")
  matches=$(printf '%s' "$keys" | awk 'NF { n++ } END { print n + 0 }')
  [ "$matches" -ne 0 ] || fail 1 "no item has theme $SEL_THEME in $RECAP"
  [ "$matches" -eq 1 ] || fail 1 "$matches items have theme $SEL_THEME, expected one, so pick one with --key: $(printf '%s' "$keys" | paste -sd, -)"
  KEY=$keys
fi

# The recap file may omit links while the last published revision holds some, and
# publish then keeps those. Starting an add or drop from an empty list would wipe
# them, so seed from the log in that case. A new item has no earlier revision.
SEED='[]'
if [ "$IS_NEW" -eq 0 ] && jq -e '.add or .drop' <<< "$EDIT" >/dev/null \
   && ! jq -e --arg k "$KEY" '.tasks[$k] | has("links")' "$RECAP" >/dev/null; then
  SEED=$("$PUBLISH" read | jq -c --arg k "$KEY" \
    '[.[] | .revisions[$k]? | select(. != null)] | (last | .links) // []') \
    || fail 1 "cannot read the iteration log for the current links of $KEY"
fi

if [ "$IS_NEW" -eq 0 ]; then
  missing=$(jq -r --arg k "$KEY" --argjson e "$EDIT" --argjson seed "$SEED" '
    (.tasks[$k].links // $seed | map(.code)) as $have
    | ($e.drop // [])[] | select(. as $c | $have | index($c) | not)' "$RECAP")
  [ -z "$missing" ] || fail 1 "item $KEY has no link with code: $(printf '%s' "$missing" | paste -sd, -)"
fi

tmp=$(mktemp "$(dirname "$RECAP")/.$(basename "$RECAP").XXXXXX") || fail 1 "cannot stage the edit"
trap 'rm -f -- "$tmp"' EXIT
# cp -p carries the original mode, which mktemp would otherwise narrow to 0600.
cp -p "$RECAP" "$tmp"
# A task's links is stored as [] rather than removed when the last one is dropped,
# because publish keeps the last revision's links for an omitted field and only an
# explicit empty list clears them.
jq --indent 2 --arg k "$KEY" --argjson new "$IS_NEW" --argjson e "$EDIT" --argjson seed "$SEED" '
  .tasks[$k] = (
    (if $new == 1 then {} else .tasks[$k] end)
    | . + ($e | del(.add, .drop, .clear_answer))
    | if $e.clear_answer then del(.answer) else . end
    | if $e.add or $e.drop then
        .links = (
          ((.links // $seed) | map(select(.code as $c | ($e.drop // []) | index($c) | not)))
          | reduce ($e.add // [])[] as $a (.; map(select(.code != $a.code)) + [$a]))
      else . end)' "$RECAP" > "$tmp" || fail 1 "cannot apply the edit to $RECAP"
jq -e --arg s "$RECAP_SCHEMA" --arg k "$KEY" '.schema == $s and (.tasks[$k] | type) == "object"' "$tmp" >/dev/null \
  || fail 1 "the edit produced an invalid recap file"
mv -f -- "$tmp" "$RECAP"
THEME=$(jq -r --arg k "$KEY" '.tasks[$k].theme // "misc"' "$RECAP")
printf 'fm-recap-item: %s %s (theme %s)\n' "$([ "$IS_NEW" -eq 1 ] && echo created || echo edited)" "$KEY" "$THEME"

[ "$PUBLISH_AFTER" -eq 1 ] || exit 0

status=0
out=$("$PUBLISH" publish "$RECAP" 2>&1) || status=$?
if [ "$status" -ne 0 ]; then
  printf '%s\n' "$out" >&2
  fail 1 "publish failed with exit $status after the file was edited"
fi
printf '%s\n' "$out" | grep -E '^(iteration|changed|waiting|url): ' || true
iteration=$(printf '%s\n' "$out" | sed -n 's/^iteration: \([0-9][0-9]*\)$/\1/p' | tail -1)
[ -n "$iteration" ] || {
  printf '%s\n' "$out" >&2
  fail 1 "publish printed no \"iteration: N\" line"
}

# The iteration read back says exactly why the item did not change, which the
# changed list alone cannot: another item of the same theme can change in the same
# publish and hide the miss.
log=$("$PUBLISH" read 2>/dev/null || true)
entry=$(jq -c --argjson n "$iteration" '[.[] | select(.seq == $n)] | first // empty' <<< "$log" 2>/dev/null || true)
if [ -n "$entry" ]; then
  if ! jq -e --arg k "$KEY" '.tasks | index($k)' <<< "$entry" >/dev/null; then
    printf 'fm-recap-item: warning: item key %s is not a task in the backlog collection, so publish ignored it and the board shows no change.\n' "$KEY" >&2
  else
    if ! jq -e --arg k "$KEY" '.revisions | has($k)' <<< "$entry" >/dev/null; then
      printf 'fm-recap-item: warning: no stored field of %s differs from its last revision, so iteration %s holds no revision for it.\n' "$KEY" "$iteration" >&2
    fi
    # The call is read from the last stored revision, not the edit, so a task that
    # asked in an earlier publish and is still not held keeps warning.
    asks=$(jq -r --arg k "$KEY" '
      [.[] | .revisions[$k]? | select(. != null)] | last // empty
      | select(.state != "done" and (.waiting | not))
      | ((.options // []) | length) as $o | ((.reply_terms // []) | length) as $t
      | if $o > 0 then $o elif $t > 0 then $t else empty end' <<< "$log" 2>/dev/null || true)
    if [ -n "$asks" ]; then
      printf 'fm-recap-item: warning: item %s asks the captain (%s options) but its backlog task is not held, so no hold records the call. Hold it with fm-captain-hold.sh or clear the options and reply terms.\n' "$KEY" "$asks" >&2
    fi
  fi
else
  changed=$(printf '%s\n' "$out" | sed -n 's/^changed: //p' | tail -1)
  if [ -n "$changed" ] && ! printf ',%s,' "$changed" | grep -qF ",$THEME,"; then
    printf 'fm-recap-item: warning: theme %s is not in the changed list (%s). Item key %s may not match a backlog task key, and publish ignores such entries.\n' \
      "$THEME" "$changed" "$KEY" >&2
  fi
fi
