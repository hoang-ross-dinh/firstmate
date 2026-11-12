#!/usr/bin/env bash
# fm-board-publish-guard.sh - Claude Stop hook that reminds the main home's
# first mate to publish the Fleet Recap board after captain-facing second-mate
# events, and the acknowledgement command that clears the reminder without a
# publish.
#
# Usage:
#   fm-board-publish-guard.sh        Stop hook mode; reads the hook payload on stdin
#   fm-board-publish-guard.sh ack    record that every event so far needs no board change
#
# WHY: the board is published by hand (bin/fm-recap-publish.sh publish), and a
# first mate that handles a second mate's decision or outcome can end its turn
# without publishing, so the captain reads a stale board until the next publish.
#
# EVENTS. A captain-facing event is one of:
#   - a line in $STATE/<id>.status for an id registered in data/secondmates.md
#     that status_is_captain_relevant (bin/fm-classify-lib.sh) accepts, such as
#     needs-decision:, done:, blocked:, failed:, and that carries an [at=<epoch>]
#     stamp; an unstamped line has no time to debounce and is skipped;
#   - a row in $STATE/branch-outcomes.jsonl (bin/fm-branch-outcome.sh) with
#     verdict "captain" for one of those ids.
# Each source is read only through its last 200 lines.
# An event counts when it is newer than the baseline: the later of the last
# board publish (the "at" of the last complete line of
# data/recap-iterations.jsonl) and the last ack ($STATE/.board-publish-ack).
#
# DECISION. The hook blocks the turn end (exit 2, one stderr message) only when
# the OLDEST counted event is at least the debounce window old, so events that
# arrive close together cost one publish. It blocks at most once per event set:
# $STATE/.board-publish-nagged records the set it last blocked for, and a new
# event changes the set. Every other case exits 0 with no output.
#
# The window is DEFAULT_WINDOW (30 seconds), or the whole number of seconds on
# the first line of config/board-publish-debounce (docs/configuration.md). An
# invalid value keeps DEFAULT_WINDOW and prints one stderr warning. The default
# is short because the rule is to publish in the same turn: the window only
# batches events that land while that turn is still running.
#
# SCOPE. It acts only in the main home: a genuine primary checkout
# (bin/fm-primary-scope-lib.sh) without a secondmate-home marker. A second-mate
# home, a task worktree, a home with no board log or no second-mate registry, a
# Cursor-delivered duplicate payload, and a session that another live session
# holds the home lock for all exit 0 silently. The last case matters because a
# lock-refused session is read-only and must not publish.
#
# An unreadable source never blocks: the hook prints one stderr line naming it
# and exits 0, because a broken reminder must not wedge the first mate's turn.
#
# FM_BOARD_PUBLISH_NOW (tests only) replaces the current epoch.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FM_ROOT="${FM_ROOT_OVERRIDE:-$(cd "$SCRIPT_DIR/.." && pwd)}"
FM_HOME="${FM_HOME:-${FM_ROOT_OVERRIDE:-$FM_ROOT}}"
STATE="${FM_STATE_OVERRIDE:-$FM_HOME/state}"
DATA="${FM_DATA_OVERRIDE:-$FM_HOME/data}"
CONFIG="${FM_CONFIG_OVERRIDE:-$FM_HOME/config}"
LOG="$DATA/recap-iterations.jsonl"
REGISTRY="$DATA/secondmates.md"
OUTCOMES="$STATE/branch-outcomes.jsonl"
ACK="$STATE/.board-publish-ack"
NAGGED="$STATE/.board-publish-nagged"
# The single owner of the default debounce window, in seconds.
DEFAULT_WINDOW=30
TAIL_LINES=200

NOW=${FM_BOARD_PUBLISH_NOW:-$(date +%s)}
case "$NOW" in ''|*[!0-9]*) NOW=$(date +%s) ;; esac

# Replace a state file whole, so a reader never sees a half-written value.
write_marker() {  # <path> <value>
  local tmp="$1.tmp.$$"
  printf '%s\n' "$2" > "$tmp" && mv -f "$tmp" "$1"
}

# A missing, unreadable, or malformed marker reads as 0: the safe direction is
# an older baseline, which can only cause a reminder, never hide one.
read_epoch() {  # <path>
  local value=''
  [ -f "$1" ] && IFS= read -r value < "$1" 2>/dev/null
  case "$value" in ''|*[!0-9]*) printf '0' ;; *) printf '%s' "$value" ;; esac
}

step_aside() {  # <reason>
  printf 'fm-board-publish-guard: %s; not checking the board this turn\n' "$1" >&2
  exit 0
}

case "${1-}" in
  ack)
    [ -d "$STATE" ] || { echo "fm-board-publish-guard: no state directory at $STATE" >&2; exit 1; }
    write_marker "$ACK" "$NOW" || { echo "fm-board-publish-guard: could not write $ACK" >&2; exit 1; }
    printf 'acknowledged board events through %s\n' "$(date -u -r "$NOW" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "@$NOW" +%Y-%m-%dT%H:%M:%SZ)"
    exit 0
    ;;
  '') ;;
  *) echo "usage: $(basename "$0") [ack]" >&2; exit 2 ;;
esac

# shellcheck source=bin/fm-primary-scope-lib.sh
. "$SCRIPT_DIR/fm-primary-scope-lib.sh"
# shellcheck source=bin/fm-hook-host-lib.sh
. "$SCRIPT_DIR/fm-hook-host-lib.sh"

PAYLOAD=$(cat 2>/dev/null || true)
fm_hook_payload_is_foreign_host "$PAYLOAD" && exit 0

fm_primary_scope_matches "$FM_ROOT" "$STATE" || exit 0
fm_root_is_secondmate_home "$FM_ROOT" && exit 0
[ -e "$LOG" ] || exit 0
[ -e "$REGISTRY" ] || exit 0

# shellcheck source=bin/fm-wake-lib.sh
. "$SCRIPT_DIR/fm-wake-lib.sh"
# shellcheck source=bin/fm-session-lock-lib.sh
. "$SCRIPT_DIR/fm-session-lock-lib.sh"
fm_session_lock_foreign_owner_live "$STATE" && exit 0

# shellcheck source=bin/fm-classify-lib.sh
. "$SCRIPT_DIR/fm-classify-lib.sh"
# shellcheck source=bin/fm-secondmate-registry-lib.sh
. "$SCRIPT_DIR/fm-secondmate-registry-lib.sh"

[ -r "$LOG" ] || step_aside "cannot read $LOG"
# The last line is torn when a publish is mid-write (no final newline), so the
# line before it is the last complete publish.
tail_two=$(tail -n 2 "$LOG" 2>/dev/null) || step_aside "cannot read $LOG"
if [ -n "$(tail -c 1 "$LOG" 2>/dev/null)" ]; then
  last=$(printf '%s\n' "$tail_two" | sed -n '1p')
else
  last=$(printf '%s\n' "$tail_two" | sed -n '$p')
fi
# The schema and seq keys precede it, so the first "at" is the iteration's own.
published_iso=$(printf '%s' "$last" | sed -n 's/^[^"]*"schema":"fm-recap-iteration\.v1","seq":[0-9]*,"at":"\([^"]*\)".*/\1/p')
published=$(fm_utc_iso_to_epoch "$published_iso" 2>/dev/null) || step_aside "no readable publish time in $LOG"

baseline=$published
acked=$(read_epoch "$ACK")
[ "$acked" -le "$baseline" ] || baseline=$acked

[ -r "$REGISTRY" ] || step_aside "cannot read $REGISTRY"
ids=''
while IFS= read -r line || [ -n "$line" ]; do
  case "$line" in '- '*) ;; *) continue ;; esac
  secondmate_registry_parse_line "$line" || continue
  ids="$ids $SECONDMATE_REGISTRY_ID"
done < "$REGISTRY"
[ -n "$ids" ] || exit 0

oldest=0 oldest_id='' newest=0 count=0
note_event() {  # <epoch> <id>
  count=$((count + 1))
  if [ "$oldest" -eq 0 ] || [ "$1" -lt "$oldest" ]; then oldest=$1; oldest_id=$2; fi
  [ "$1" -le "$newest" ] || newest=$1
}

for id in $ids; do
  file="$STATE/$id.status"
  [ -e "$file" ] || continue
  [ -r "$file" ] || step_aside "cannot read $file"
  # ponytail: only the last $TAIL_LINES lines; a burst longer than that since
  # the baseline loses its oldest events, which only shortens the debounce.
  # awk keeps only lines stamped after the baseline, so the per-line classifier
  # runs on a handful of lines instead of the whole tail.
  while IFS= read -r line; do
    status_is_captain_relevant "$line" || continue
    at=$(status_line_at_epoch "$line") || continue
    note_event "$at" "$id"
  done < <(tail -n "$TAIL_LINES" "$file" 2>/dev/null | awk -v b="$baseline" '
    { head = $0; sub(/:.*/, "", head)
      if (match(head, /\[at=[0-9]+\]/)) {
        at = substr(head, RSTART + 4, RLENGTH - 5) + 0
        if (at > b) print
      } }')
done

if [ -e "$OUTCOMES" ]; then
  [ -r "$OUTCOMES" ] || step_aside "cannot read $OUTCOMES"
  command -v jq >/dev/null 2>&1 || step_aside "jq is missing, so $OUTCOMES cannot be read"
  while read -r at task; do
    case " $ids " in *" $task "*) note_event "$at" "$task" ;; esac
  done < <(tail -n "$TAIL_LINES" "$OUTCOMES" 2>/dev/null | jq -Rr --argjson b "$baseline" '
    fromjson? | select(type == "object" and .verdict == "captain"
      and (.epoch | type) == "number" and .epoch > $b and (.task | type) == "string")
    | "\(.epoch) \(.task)"' 2>/dev/null)
fi

[ "$count" -gt 0 ] || exit 0

window=$DEFAULT_WINDOW
if [ -e "$CONFIG/board-publish-debounce" ]; then
  configured=''
  IFS= read -r configured < "$CONFIG/board-publish-debounce" 2>/dev/null
  configured=${configured//[[:space:]]/}
  case "$configured" in
    ''|*[!0-9]*) echo "fm-board-publish-guard: config/board-publish-debounce must be whole seconds; using $DEFAULT_WINDOW" >&2 ;;
    *) window=$((10#$configured)) ;;
  esac
fi

age=$((NOW - oldest))
[ "$age" -ge "$window" ] || exit 0

signature="$newest $count"
[ "$(cat "$NAGGED" 2>/dev/null)" != "$signature" ] || exit 0
write_marker "$NAGGED" "$signature" 2>/dev/null || true

# Seconds read better than "0 min" at the short default window.
if [ "$age" -lt 120 ]; then age_text="${age}s"; else age_text="$((age / 60)) min"; fi
printf 'Fleet Recap board is stale: %s captain-facing second-mate event(s) since the last board publish, the oldest from %s %s ago. Publish the board now (bin/fm-recap-publish.sh publish <recap.json>). If none of them changes the board, run bin/fm-board-publish-guard.sh ack instead.\n' \
  "$count" "$oldest_id" "$age_text" >&2
exit 2
