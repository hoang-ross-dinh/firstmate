#!/usr/bin/env bash
# fm-recap-publish.sh - publish the Fleet Recap board and record one iteration.
#
# The Fleet Recap board is the captain's review surface for fleet work. Each
# publication is one iteration in an append-only log, each backlog task is one
# ticket, and a task gets a new revision only when its stored fields changed.
# The backlogs stay the system of record: this command reads tasks through
# bin/fm-bearings-snapshot.sh --json and bin/fm-tasks-axi.sh, never from a
# backlog file, and makes no Jira call.
#
# The board is a read-only report surface, so publish and refresh build it while
# away mode is active by passing --allow-away to the snapshot; plain /bearings
# keeps its refusal.
#
# Usage:
#   fm-recap-publish.sh publish <recap.json>
#   fm-recap-publish.sh refresh
#   fm-recap-publish.sh read
#   fm-recap-publish.sh path
#
# publish   Append exactly one iteration to the log, then build the board
#           through `fm-bearings-board.sh build`, which owns the Lavish session
#           (establish, reopen an ended session, bind, arm). Output is that
#           build's output followed by the facts for the one chat line:
#             iteration: <n>
#             changed: <theme codes, comma separated, or ->
#             waiting: <tasks waiting on the captain>
#             url: <board url>
# refresh   Rebuild the board from the existing log with no new iteration, so a
#           first-mate reply to a comment shows without costing an iteration.
# read      Print the readable log entries as one JSON array. An unreadable
#           line is skipped and reported on stderr, never rewritten.
# path      Print the iteration log path.
#
# <recap.json> is fm-recap.v1, composed by the first mate:
#   { "schema": "fm-recap.v1",
#     "tasks": { "<task-key>": { "summary": "...", "emoji": "...",
#                                "theme": "LW", "reply_terms": ["merge"],
#                                "close": "release",
#                                "on_hold": "waiting: first review feedback",
#                                "links": [{ "kind": "ticket", "code": "ABC-1",
#                                            "url": "https://...", "text": "..." }] } } }
# A task key is the task id for the main home and "<home>:<id>" for a
# secondmate home. Every field is optional. A task without an entry, or an entry
# without a field, keeps the value from its last revision, and a new task falls
# back to theme "misc" with an empty summary and emoji. close is "done" or
# "release" and only matters for a task the captain answers. on_hold is a short
# string naming the outside event a task waits for after the captain put it on
# hold: a non-empty string marks the task and the board shows an "On Hold" badge
# with that text on the row and in the detail, and an empty string clears the
# mark. Only the first mate sets it, so the backlog does not carry it and an
# omitted field keeps the last value. A longer string than 200 characters or any
# non-string value is rejected whole, like any other bad field. links is the list of
# tickets and merge requests the board shows as chips on the row and under
# "Tickets & MRs" in the detail panel: kind is "ticket" or "mr", code and an
# http(s) url are required, text is an optional short title. A publish with any
# other kind, an empty code, or a url that is not http(s) is rejected whole, like
# any other bad field, and the board makes no network call for a link. An empty
# list clears a task's links.
#
# THE LOG is $DATA/recap-iterations.jsonl in the main home's gitignored data/
# directory, one fm-recap-iteration.v1 JSON object per line, written only here.
# An entry holds its sequence number, the key of every task present, and the new
# revisions (key -> stored fields) for the tasks that changed. Appending takes a
# lock, writes one complete line, and starts that line on a new line when the
# file does not end in one, so an earlier line is never rewritten. A reader
# skips and reports a line it cannot read, which includes an unterminated last
# line left by a torn write.
#
# config/recap-jira-base (optional, local, gitignored) holds one https URL prefix
# such as https://jira.example.test/browse/ that the board puts before a Jira key
# to make a link. Without it a key shows as plain text.
#
# config/recap-ticket-url (optional, local, gitignored) derives ticket chips from
# a task title. Line 1 is an http(s) URL template holding {key}, an optional line
# 2 is the key regex (default [A-Z][A-Z0-9]+-[0-9]+). Compose appends one ticket
# chip per distinct key in the title whose code is not already in the task's
# links, after the explicit links. An invalid file disables derivation with one
# warning on stderr and the publish still succeeds.
#
# THE BOARD PAYLOAD is fm-recap-board.v1: the last 30 iterations are navigable,
# and every task carries all of its revisions in full, so the board renders each
# one as the same card. The log keeps everything.
#
# FM_RECAP_COLLECT_FILE (tests only) replaces the backlog collection with a
# JSON file of the shape { "tasks": [...], "warnings": [...] }.
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FM_ROOT="${FM_ROOT_OVERRIDE:-$(cd "$SCRIPT_DIR/.." && pwd)}"
FM_HOME="${FM_HOME:-$FM_ROOT}"
DATA="${FM_DATA_OVERRIDE:-$FM_HOME/data}"
CONFIG="${FM_CONFIG_OVERRIDE:-$FM_HOME/config}"
LOG="$DATA/recap-iterations.jsonl"
LOG_LOCK="$DATA/.recap-iterations.lock"

ITERATION_SCHEMA=fm-recap-iteration.v1
RECAP_SCHEMA=fm-recap.v1
BOARD_SCHEMA=fm-recap-board.v1
WINDOW=30

# shellcheck source=bin/fm-wake-lib.sh
. "$SCRIPT_DIR/fm-wake-lib.sh"
# shellcheck source=bin/fm-secondmate-registry-lib.sh
. "$SCRIPT_DIR/fm-secondmate-registry-lib.sh"

usage() {
  awk '
    NR == 1 { next }
    /^#/ { sub(/^# ?/, ""); print; next }
    { exit }
  ' "$0"
}

fail() {
  printf 'fm-recap-publish: %s\n' "$*" >&2
  exit 1
}

# --- iteration log ------------------------------------------------------------

# The readable entries as one JSON array. An unterminated last line is dropped
# before parsing because a torn write leaves exactly that shape.
read_log() {
  local unterminated=0 total=0 valid entries
  if [ ! -f "$LOG" ]; then
    printf '[]\n'
    return 0
  fi
  [ -z "$(tail -c1 "$LOG")" ] || unterminated=1
  total=$(awk 'END { print NR }' "$LOG")
  if [ "$unterminated" -eq 1 ]; then
    entries=$(sed '$d' "$LOG" | jq -R -c --arg s "$ITERATION_SCHEMA" \
      'fromjson? | select(type == "object" and .schema == $s and (.seq | type == "number"))')
  else
    entries=$(jq -R -c --arg s "$ITERATION_SCHEMA" \
      'fromjson? | select(type == "object" and .schema == $s and (.seq | type == "number"))' "$LOG")
  fi
  valid=$(printf '%s' "$entries" | awk 'NF { n++ } END { print n + 0 }')
  if [ "$valid" -ne "$total" ]; then
    printf 'fm-recap-publish: skipped %s unreadable line(s) in %s (incomplete last line: %s)\n' \
      "$((total - valid))" "$LOG" "$([ "$unterminated" -eq 1 ] && echo yes || echo no)" >&2
  fi
  printf '%s' "$entries" | jq -s -c 'sort_by(.seq)'
}

append_entry() {  # <entry-json>
  fm_lock_acquire_wait "$LOG_LOCK" || fail "cannot lock the iteration log"
  # shellcheck disable=SC2064
  trap "fm_lock_release '$LOG_LOCK'" EXIT
  [ ! -s "$LOG" ] || [ -z "$(tail -c1 "$LOG")" ] || printf '\n' >> "$LOG"
  printf '%s\n' "$1" >> "$LOG" || fail "cannot append to $LOG"
}

# --- backlog collection -------------------------------------------------------

# Parse the `key: value` block of `tasks-axi show --full` into a JSON object.
# Quoted values are JSON strings, bare values are plain text.
task_from_show() {  # <show-output>
  printf '%s\n' "$1" | jq -R -s '
    split("\n")
    | map(select(test("^  [a-z_]+: ")) | capture("^  (?<k>[a-z_]+): (?<v>.*)$"))
    | map({key: .k, value: (.v as $s | ((try ($s | fromjson | select(type == "string")) catch null) // $s))})
    | from_entries'
}

# One home'"'"'s tasks as a JSON array, or nothing and a failure when its backlog
# cannot be read through tasks-axi.
collect_home() {  # <home-name> <home-dir> <snapshot-prs-json>
  local name=$1 dir=$2 prs=$3 listing id show rows='[]' task
  local run=(env)
  if [ "$name" != main ]; then
    run+=(-u FM_DATA_OVERRIDE -u FM_STATE_OVERRIDE "FM_HOME=$dir")
  fi
  listing=$("${run[@]}" "$SCRIPT_DIR/fm-tasks-axi.sh" list --limit 1000 2>/dev/null) || return 1
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    show=$("${run[@]}" "$SCRIPT_DIR/fm-tasks-axi.sh" show "$id" --full 2>/dev/null) || return 1
    task=$(task_from_show "$show") || return 1
    rows=$(jq -c --arg home "$name" --argjson t "$task" --argjson prs "$prs" '
      def clean($v; $none): if ($v == null) or ($v == "-") or ($v == $none) then "" else $v end;
      def url($re): ((($t.links // "") | [scan("https?://[^\\s,]+")] | map(select(test($re))) | first) // "");
      . + [{
        id: $t.id,
        key: (if $home == "main" then $t.id else ($home + ":" + $t.id) end),
        home: $home,
        kind: clean($t.kind; ""),
        repo: clean($t.repo; ""),
        state: ($t.state // ""),
        title: ($t.title // ""),
        held: (($t.held // "no") == "yes"),
        hold_kind: clean($t.hold_kind; ""),
        hold_until: clean($t.hold_until; ""),
        hold_reason: clean($t.hold_reason; ""),
        blockers: clean($t.blocked_by; "none"),
        pr_url: (url("/(pull|merge_requests)/") as $u
          | if $u != "" then $u else (($prs[$t.id]) // "") end),
        issue_url: url("/(issues|browse)/"),
        note: ($t.body // "")
      }]' <<< "$rows") || return 1
  done < <(printf '%s\n' "$listing" | sed -n 's/^  \([A-Za-z0-9._-][A-Za-z0-9._-]*\),.*/\1/p')
  printf '%s\n' "$rows"
}

# { tasks: [...], warnings: [...] } from every readable backlog.
collect() {
  local snapshot prs warnings tasks='[]' rows line today
  if [ -n "${FM_RECAP_COLLECT_FILE:-}" ]; then
    jq -c . "$FM_RECAP_COLLECT_FILE" || fail "cannot read the collect file"
    return 0
  fi
  snapshot=$("$SCRIPT_DIR/fm-bearings-snapshot.sh" --json --all-recorded-prs --allow-away) \
    || fail "cannot read the bearings snapshot"
  prs=$(jq -c '[.recorded_prs[]? | {key: .id, value: .url}] | from_entries' <<< "$snapshot")
  warnings=$(jq -c '
    [(.gates[]? | select(.id | test("^\\(")) | {id, title: (.title // .id), reason: (.reason // "")}),
     (.secondmates[]? | select(.state == "unknown" or .contradiction == true)
       | {id, title: ("secondmate " + .id), reason: (.reason // .doing // "")})]' <<< "$snapshot")
  if rows=$(collect_home main "$FM_HOME" "$prs"); then
    tasks=$rows
  else
    warnings=$(jq -c '. + [{id: "(main-backlog)", title: "main backlog", reason: "tasks-axi could not read it"}]' <<< "$warnings")
  fi
  if [ -f "$DATA/secondmates.md" ]; then
    while IFS= read -r line; do
      case "$line" in '- '*) ;; *) continue ;; esac
      secondmate_registry_parse_line "$line" || continue
      if [ "$SECONDMATE_REGISTRY_REMOTE" = 1 ] || [ ! -d "$SECONDMATE_REGISTRY_HOME" ]; then
        warnings=$(jq -c --arg id "$SECONDMATE_REGISTRY_ID" \
          '. + [{id: ("(" + $id + ")"), title: ("secondmate " + $id), reason: "its backlog is not readable from here"}]' <<< "$warnings")
        continue
      fi
      if rows=$(collect_home "$SECONDMATE_REGISTRY_ID" "$SECONDMATE_REGISTRY_HOME" "$prs"); then
        tasks=$(jq -c '. + $rows' --argjson rows "$rows" <<< "$tasks")
      else
        warnings=$(jq -c --arg id "$SECONDMATE_REGISTRY_ID" \
          '. + [{id: ("(" + $id + ")"), title: ("secondmate " + $id), reason: "tasks-axi could not read its backlog"}]' <<< "$warnings")
      fi
    done < "$DATA/secondmates.md"
  fi
  today=$(date -u +%F)
  jq -c --argjson warnings "$warnings" --arg today "$today" '
    {tasks: (map(. + {waiting: (.held and .hold_kind == "captain"
      and (.hold_until == "" or .hold_until <= $today))})),
     warnings: $warnings}' <<< "$tasks"
}

# --- revisions ----------------------------------------------------------------

validate_recap() {  # <recap.json>
  jq -e --arg schema "$RECAP_SCHEMA" '
    type == "object" and .schema == $schema and (.tasks | type == "object")
    and ([.tasks[] | type == "object"
      and ((has("summary") | not) or (.summary | type == "string"))
      and ((has("emoji") | not) or (.emoji | type == "string"))
      and ((has("theme") | not) or (.theme | type == "string" and test("^[A-Za-z0-9._-]{1,16}$")))
      and ((has("close") | not) or (.close == "done" or .close == "release"))
      and ((has("on_hold") | not) or (.on_hold | type == "string" and length <= 200))
      and ((has("reply_terms") | not) or (.reply_terms | type == "array"
        and ([.[] | type == "string" and length > 0 and length <= 64] | all)))
      and ((has("links") | not) or (.links | type == "array"
        and ([.[] | type == "object"
          and (.kind == "ticket" or .kind == "mr")
          and (.code | type == "string" and length > 0 and length <= 64)
          and (.url | type == "string" and test("^https?://[^\\s]+$"))
          and ((has("text") | not) or (.text | type == "string"))] | all)))] | all)' "$1" >/dev/null
}

# The ticket-chip derivation setting from config/recap-ticket-url, as the globals
# TICKET_TPL and TICKET_RE. Both stay empty when the file is absent, unreadable,
# or a symlink. An invalid template or regex warns once and leaves both empty.
TICKET_TPL=''
TICKET_RE=''
load_ticket_derivation() {
  local f="$CONFIG/recap-ticket-url" tpl='' re=''
  [ -f "$f" ] && [ ! -L "$f" ] || return 0
  { IFS= read -r tpl || true; IFS= read -r re || true; } < "$f" 2>/dev/null || return 0
  tpl=${tpl%$'\r'}; re=${re%$'\r'}
  [ -n "$re" ] || re='[A-Z][A-Z0-9]+-[0-9]+'
  case "$tpl" in
    http://*'{key}'*|https://*'{key}'*) ;;
    *) printf 'fm-recap-publish: %s: line 1 must be an http(s) URL holding {key}; ticket chips are not derived\n' "$f" >&2; return 0 ;;
  esac
  case "$tpl" in
    *[[:space:]]*) printf 'fm-recap-publish: %s: the URL template holds whitespace; ticket chips are not derived\n' "$f" >&2; return 0 ;;
  esac
  if ! jq -n --arg re "$re" '"" | test($re)' >/dev/null 2>&1; then
    printf 'fm-recap-publish: %s: line 2 is not a valid regex; ticket chips are not derived\n' "$f" >&2
    return 0
  fi
  TICKET_TPL=$tpl
  TICKET_RE=$re
}

# The new iteration entry from the prior entries, the collection, and the recap.
compose_entry() {  # <entries.json> <collected.json> <recap.json>
  jq -c -n --arg schema "$ITERATION_SCHEMA" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg tpl "$TICKET_TPL" --arg re "$TICKET_RE" \
    --slurpfile entries "$1" --slurpfile collected "$2" --slurpfile recap "$3" '
    # Ticket chips for the distinct keys in a title, after the explicit links.
    # A derived url that is not http(s) without whitespace is dropped.
    def derived($title; $have):
      if $tpl == "" then []
      else (reduce ($title | match($re; "g") | .string) as $k ([]; if index($k) then . else . + [$k] end)) as $keys
        | [$keys[] | . as $k | select($have | index($k) | not)
            | {kind: "ticket", code: $k, url: ($tpl | split("{key}") | join($k))}
            | select(($k | length) > 0 and ($k | length) <= 64 and (.url | test("^https?://[^\\s]+$")))]
      end;
    ($entries[0]) as $entries
    | ($collected[0]) as $c
    | ($recap[0].tasks) as $fm
    | (reduce ($entries[] | .revisions | to_entries[]) as $r ({}; .[$r.key] = $r.value)) as $last
    | ($entries | map(.seq) | max // 0) as $prev
    | [$c.tasks[]
        | . as $t
        | ($last[$t.key] // {}) as $old
        | ($fm[$t.key] // {}) as $mine
        | ($t | del(.key, .id)) + {id: $t.id}
        + {
            summary: ($mine.summary // $old.summary // ""),
            emoji: ($mine.emoji // $old.emoji // ""),
            theme: ($mine.theme // $old.theme // "misc"),
            reply_terms: ($mine.reply_terms // $old.reply_terms // []),
            close: ($mine.close // $old.close // "")
          }
        # links are stored only when present, so a task without any keeps its
        # earlier revision unchanged.
        # on_hold is stored only while set, so an unmarked task keeps its
        # earlier revision unchanged and a cleared mark drops the field.
        + (($mine.on_hold // $old.on_hold // "") as $h | if $h != "" then {on_hold: $h} else {} end)
        + (($mine.links // $old.links // []) as $l
            | ($l + derived($t.title // ""; [$l[].code])) as $l
            | if ($l | length) > 0 then {links: $l} else {} end)
        | {key: $t.key, value: .}
        | select(.value != $old)] as $changed
    | {
        schema: $schema,
        seq: ($prev + 1),
        at: $at,
        tasks: [$c.tasks[].key],
        revisions: ($changed | from_entries),
        changed_themes: ([$changed[].value.theme] | unique),
        waiting: ([$c.tasks[] | select(.waiting)] | length),
        warnings: $c.warnings
      }'
}

# --- board payload ------------------------------------------------------------

# Comment notes and their replies from the inbox, matched by their task tag.
collect_comments() {
  local receipts
  receipts=$("$SCRIPT_DIR/fm-inbox.sh" receipts --all-pending --all-handled --all-replies 2>/dev/null) \
    || { printf '[]\n'; return 0; }
  jq -c '
    ([.pending[]?, .handled[]?]) as $notes
    | [$notes[]
      | select(.body | test("^\\[recap task=[^ ]+ iteration=[0-9]+( answer)?\\] "))
      | (.body | capture("^\\[recap task=(?<task>[^ ]+) iteration=(?<iteration>[0-9]+)(?<answer> answer)?\\] (?<text>.*)$"; "s")) as $c
      | {key: $c.task, iteration: ($c.iteration | tonumber), kind: (if $c.answer then "answer" else "comment" end), text: $c.text, at: .at, id: .id,
         reply: (if .reply == null then null else {text: (.reply.body // .reply.text // ""), at: (.reply.at // "")} end)}]' \
    <<< "$receipts" 2>/dev/null || printf '[]\n'
}

# The Jira base URL is a private setting: the first line of config/recap-jira-base,
# an https URL the board prefixes to a Jira key. Absent, unreadable, symlinked, or
# malformed means no base, and the board shows a key as plain text.
jira_base() {
  local f="$CONFIG/recap-jira-base" line
  [ -f "$f" ] && [ ! -L "$f" ] || return 0
  IFS= read -r line < "$f" || true
  case "$line" in
    https://*[[:space:]]*|https://) return 0 ;;
    https://*) printf '%s\n' "$line" ;;
  esac
}

compose_board() {  # <entries.json> <home-name>
  jq -c -n --arg schema "$BOARD_SCHEMA" --arg home "$2" --arg jira "$(jira_base)" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --argjson window "$WINDOW" --slurpfile entries "$1" '
    ($entries[0] | sort_by(.seq)) as $entries
    | ($entries | last) as $latest
    | ($latest.seq - $window) as $floor
    | {
      schema: $schema,
      home: $home,
      jira_base: $jira,
      generated: $at,
      iteration: $latest.seq,
      window: $window,
      iterations: [$entries[] | select(.seq > $floor) | {seq, at, tasks, waiting, changed_themes}],
      warnings: ($latest.warnings // []),
      tasks: (
        [$entries[] | .seq as $seq | .revisions | to_entries[] | {key: .key, seq: $seq, rev: .value}]
        | group_by(.key)
        | map(
            (.[-1].rev) as $cur
            # Every revision stays in full: a one-line older tail rendered in a
            # second style and left the oldest card without a diff.
            # ponytail: payload grows with the log, cap by count if it gets large
            | {
              key: .[0].key,
              id: $cur.id,
              home: $cur.home,
              revisions: ([.[] | .rev + {iter: .seq}] | reverse)
            })
      )
    }'
}

attach_comments() {  # <board.json> <comments.json>
  jq -c --slurpfile comments "$2" '
    .tasks |= map(. as $t | .comments = [$comments[0][] | select(.key == $t.key)])' "$1"
}

build_board() {  # <entries.json> <comments.json> <board-out.json>
  local tmp
  tmp=$(mktemp "${TMPDIR:-/tmp}/fm-recap-board.XXXXXX") || return 1
  if compose_board "$1" "$(home_name)" > "$tmp" && attach_comments "$tmp" "$2" > "$3"; then
    rm -f -- "$tmp"
    return 0
  fi
  rm -f -- "$tmp"
  return 1
}

home_name() {
  local home=${FM_HOME%/}
  printf '%s/%s\n' "$(basename "$(dirname "$home")")" "$(basename "$home")"
}

run_build() {  # <board.json>
  local out url
  out=$("$SCRIPT_DIR/fm-bearings-board.sh" build "$1") || { printf '%s\n' "$out"; return 1; }
  printf '%s\n' "$out"
  url=$(printf '%s\n' "$out" | sed -n 's/^[[:space:]]*url:[[:space:]]*"\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' | head -1)
  printf '%s\n' "${url:-}"
}

command_publish() {
  local recap=${1-} work entries collected entry board out iteration themes waiting url
  [ "$#" -eq 1 ] || { usage >&2; exit 2; }
  command -v jq >/dev/null 2>&1 || fail "jq is required"
  [ -f "$recap" ] || fail "recap data does not exist: $recap"
  jq empty "$recap" 2>/dev/null || fail "recap data is not valid JSON: $recap"
  validate_recap "$recap" || fail "recap data does not satisfy $RECAP_SCHEMA: $recap"
  mkdir -p "$DATA"
  work=$(mktemp -d "${TMPDIR:-/tmp}/fm-recap-publish.XXXXXX") || fail "cannot stage the publish"
  entries="$work/entries.json"; collected="$work/collected.json"
  load_ticket_derivation
  read_log > "$entries" || { rm -rf -- "$work"; fail "cannot read the iteration log"; }
  collect > "$collected" || { rm -rf -- "$work"; fail "cannot collect the backlogs"; }
  entry=$(compose_entry "$entries" "$collected" "$recap") \
    || { rm -rf -- "$work"; fail "cannot compose the iteration entry"; }
  # The new entry joins the readable entries so the board shows this iteration.
  jq -c --argjson e "$entry" '. + [$e]' "$entries" > "$work/with-entry.json"
  collect_comments > "$work/comments.json"
  board="$work/board.json"
  build_board "$work/with-entry.json" "$work/comments.json" "$board" \
    || { rm -rf -- "$work"; exit 1; }
  # Record the iteration only once the board payload exists, then build it.
  append_entry "$entry"
  iteration=$(jq -r .seq <<< "$entry")
  themes=$(jq -r '.changed_themes | if length == 0 then "-" else join(",") end' <<< "$entry")
  waiting=$(jq -r .waiting <<< "$entry")
  out=$(run_build "$board") || { rm -rf -- "$work"; printf '%s\n' "$out"; fail "iteration $iteration recorded but the board build failed"; }
  rm -rf -- "$work"
  url=$(printf '%s\n' "$out" | tail -1)
  printf '%s\n' "$out" | sed '$d'
  printf 'iteration: %s\nchanged: %s\nwaiting: %s\nurl: %s\n' "$iteration" "$themes" "$waiting" "$url"
}

command_refresh() {
  local work entries out
  work=$(mktemp -d "${TMPDIR:-/tmp}/fm-recap-publish.XXXXXX") || fail "cannot stage the refresh"
  read_log > "$work/entries.json"
  [ "$(jq length "$work/entries.json")" -gt 0 ] || { rm -rf -- "$work"; fail "no iteration has been published yet"; }
  collect_comments > "$work/comments.json"
  build_board "$work/entries.json" "$work/comments.json" "$work/board.json" \
    || { rm -rf -- "$work"; exit 1; }
  entries=$(jq -r 'last | .seq' "$work/entries.json")
  out=$(run_build "$work/board.json") || { rm -rf -- "$work"; printf '%s\n' "$out"; fail "the board build failed"; }
  rm -rf -- "$work"
  printf '%s\n' "$out" | sed '$d'
  printf 'iteration: %s\nurl: %s\n' "$entries" "$(printf '%s\n' "$out" | tail -1)"
}

case "${1-}" in
  publish) shift; command_publish "$@" ;;
  refresh) shift; command_refresh ;;
  read) read_log ;;
  path) printf '%s\n' "$LOG" ;;
  -h|--help|help) usage ;;
  *) usage >&2; exit 2 ;;
esac
