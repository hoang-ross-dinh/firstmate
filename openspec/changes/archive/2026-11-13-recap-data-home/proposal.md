## Why

The first mate keeps the Fleet Recap input file, `recap.json`, in a session scratchpad under `/tmp`.
A machine restart wiped that file and the first mate had to rebuild it by hand from a snapshot and the iteration log.
The iteration log already lives in the gitignored `data/` directory and survived.

## What Changes

- `bin/fm-recap-publish.sh` gains a default recap path, `data/recap.json` in the firstmate home, and `publish` uses it when no path is given. An explicit path still wins.
- `bin/fm-recap-publish.sh recap-path` prints that default path, so every command shares one definition of it.
- `bin/fm-recap-publish.sh restore [<recap.json>] [--force]` rebuilds the recap file from the iteration log. For each task in the newest iteration it keeps the first mate fields of the task's last stored revision. It refuses to replace a non-empty file unless `--force` is given.
- `bin/fm-recap-item.sh` uses the same default when its first argument is not a recap path. A first argument that holds a slash or ends in `.json` is a path, so every existing call keeps working.
- The log holds enough to rebuild every first mate field. It cannot return an answer, which a revision keeps only for its own publish. It also cannot return a recap entry for a key that never was a backlog task, nor the difference between an explicit link and a ticket chip derived from a title.

Out of scope: board visuals, other recap fields, and any change to the log format.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `recap-iteration-log`: the recap file has a durable default location, and a command restores it from the log.
- `recap-item-command`: the command uses the default recap file when no path is given.

## Impact

- `bin/fm-recap-publish.sh`, `bin/fm-recap-item.sh`, and their tests.
- The bearings skill text that tells the first mate how to publish.
- The log format and the board payload are unchanged.
