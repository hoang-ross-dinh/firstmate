## 1. Publish command

- [x] 1.1 Add the default recap path `data/recap.json` and the `recap-path` command
- [x] 1.2 Let `publish` run without a path and name the restore command when the default file is missing
- [x] 1.3 Add `restore` with the overwrite refusal, `--force`, an optional path, and validation of the rebuilt file

## 2. Item command

- [x] 2.1 Use the default recap file from publish when the first argument is not a recap path

## 3. Tests and text

- [x] 3.1 Add tests for each scenario, using synthetic data only
- [x] 3.2 Tell the first mate about the default file and `restore` in the bearings skill and the script index
