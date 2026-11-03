---
name: update-my-firstmate
description: >-
  Merge upstream origin/main into this home's local main when local main has diverged from it, verify the result, and prepare the push to the fork.
  Use when the captain invokes /update-my-firstmate (e.g. "/update-my-firstmate", "merge origin into my main", "update firstmate, my main has diverged").
  Use it instead of /updatefirstmate when the primary home works on a local main that carries its own commits and tracks a fork.
user-invocable: true
metadata:
  internal: true
---

# update-my-firstmate

Bring `origin/main` into this home's local `main` with a merge, test it, and hand the captain the push command for the fork.
`/updatefirstmate` is fast-forward only, so it skips a home whose `main` has diverged from `origin/main`.
This skill fills that gap for the primary home.
Here `origin` is upstream, which this home never pushes to, and `fork` is the remote that local `main` tracks.

Never push, never run `/updatefirstmate`, never force, never stash, and never `reset --hard`.
The git stash stack is shared across worktrees, so a stash here can pop into another session's work.
The home must never be left half-merged: it is either on its old `main` or on a tested, fully merged `main`.
Give the captain the outcome under `AGENTS.md` section 9, in plain words.

`<home>` below is `git rev-parse --show-toplevel` of the primary home.
Run every git command as `git -C <home> ...`.

## 1. Preconditions

Stop and report the first one that fails.
Change nothing.

1. `git -C <home> branch --show-current` prints `main`.
2. `git -C <home> status --porcelain` prints nothing.
3. `git -C <home> remote` lists both `origin` and `fork`.
4. No live crewmate works on this repository's shared tracked material.
   Read `project=` in `state/*.meta` and check each match with `bin/fm-crew-state.sh <id>`.
   A merge moves files under such a crewmate.
5. `git -C <home> fetch origin` and `git -C <home> fetch fork` both succeed.

## 2. Classify

Compare `main` with `origin/main`:

```sh
git -C <home> rev-list --left-right --count main...origin/main
```

- `0 0` or `N 0`: nothing to merge from upstream.
  Report that `main` is current, and say how many local commits are not on `fork/main`.
  Continue at step 5 only when `fork/main..main` is non-empty.
- `0 N`: `main` is behind and can fast-forward.
  Stop and point the captain at `/updatefirstmate`.
  Do not run it.
- `N M` with both non-zero: diverged.
  Continue.

## 3. Merge

Test whether the merge is clean without touching the home's files:

```sh
git -C <home> merge-tree --write-tree --name-only main origin/main
```

A zero exit means no conflict.
Run `git -C <home> merge --no-edit origin/main` in the live home and go to step 4.

A non-zero exit means conflict.
The live home stays untouched.
If a merge was already started in the live home, run `git -C <home> merge --abort` first.
Report the conflicting files from the `merge-tree` output and the commits on both sides:

```sh
git -C <home> log --left-right --cherry-pick --format='%m %h %an %s' main...origin/main
```

Then resolve in an isolated worktree:

1. Create it from `main` on a scratch branch: `git -C <home> worktree add -b merge-origin-main <tmp-dir> main`.
2. Run `git -C <tmp-dir> merge origin/main`, then resolve each conflicting file by hunk.
   - Take upstream for a change that upstream commits own.
   - Keep the captain's side for a change that the captain's own commits own.
   - Use the `%an` column of the log above to tell them apart.
   - When one hunk holds both, merge both intents by hand.
     Never use a blanket `-X ours` or `-X theirs`.
3. Complete the merge commit in `<tmp-dir>`.
4. Run the test suite there (step 4).
5. Only if the tests pass, fast-forward the live home: `git -C <home> merge --ff-only merge-origin-main`.
   If it is not a fast-forward, `main` moved during the work.
   Stop, report it, and leave the home alone.
6. Remove the scratch: `git -C <home> worktree remove <tmp-dir>` then `git -C <home> branch -d merge-origin-main`.
   If the tests failed, keep the worktree and branch for the captain and report their paths.

## 4. Test

Run the repo suite on the merged tree.
`<dir>` is `<home>` for a clean merge and `<tmp-dir>` for a resolved one:

```sh
<dir>/bin/fm-test-run.sh --all
```

`CONTRIBUTING.md` owns the test commands.
Report the not-ok count.
On any failure, stop and report the failing scripts.
A clean merge already made in the live home cannot be undone with `reset --hard`.
Report the failure and let the captain choose between a fix commit and `git -C <home> revert -m 1 HEAD`.

## 5. Scan what the push would publish

The fork is public, so read everything in `fork/main..main` before offering the push:

```sh
git -C <home> log fork/main..main --format='%h %an <%ae> | %cn <%ce> | %s'
git -C <home> diff fork/main..main
```

1. Emails.
   Accept only the identity in `git -C <home> config user.email` and the authors and committers already on `origin/main` (`git -C <home> log origin/main --format='%ae%n%ce'`).
   List every other author or committer email with its commit.
2. Content.
   Search the added lines of the diff for credentials (private key headers, access key or token patterns, `password=`), ticket keys (`[A-Z]{2,}-[0-9]+`), non-public host names, absolute home paths, and every internal name the captain's `data/captain.md` marks as private.
   List each hit with its file and commit.
3. Local files that leak by name.
   Check that the diff adds nothing under `data/`, `state/`, `config/`, `projects/`, or `.no-mistakes/`.

Any finding means the captain must decide before pushing.
Report each one and still print the command in step 6, marked as blocked until the captain clears the findings.

## 6. Hand over the push

Print this exact line for the captain to run, with `<home>` filled in:

```
! git -C <home> push fork main
```

State the final `main` commit, the test result, and the scan result.
This skill never runs that command.
