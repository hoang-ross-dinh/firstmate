## ADDED Requirements

### Requirement: Set or clear the item answer
WHEN the command receives `--answer-to <id>` with `--answer-file <path>`, it SHALL set the item's answer to that note id and the text of the file, keeping line breaks.
WHEN the command receives `--clear-answer`, it SHALL remove the answer field from the item.
IF the note id is not 1 to 64 letters, digits, dots, dashes, or underscores, the file does not exist, the text is blank or longer than 20000 characters, one of `--answer-to` and `--answer-file` is given without the other, or `--clear-answer` comes with `--answer-file`, THEN the command SHALL exit with status 2 before it writes the file or calls publish.

#### Scenario: Set then clear
- **WHEN** the command receives a note id and a multi-line Markdown file, and later `--clear-answer`
- **THEN** the item holds the answer with its line breaks, then holds no answer field, and no other field changes
- Proven by `test_answer_file_sets_the_item_answer_and_clear_answer_removes_it`

#### Scenario: Bad answer input
- **WHEN** the command receives a half-given, blank, oversized, or conflicting answer flag set
- **THEN** it exits with status 2 and the file is unchanged
- Proven by `test_a_bad_answer_flag_set_exits_2_before_anything_is_written`
