## MODIFIED Requirements

### Requirement: Field and link edits
WHEN the command receives `--reply-term` at least once, it SHALL replace the whole reply_terms list with the given terms.
WHEN the command receives `--clear-reply-terms`, it SHALL set reply_terms to an empty list.
IF the command receives `--clear-reply-terms` together with `--reply-term`, THEN it SHALL exit with status 2.
WHEN the command receives `--add-link`, it SHALL add the link and replace any link with the same code.
WHEN the command receives `--drop-link`, it SHALL remove the link with that code.
IF a dropped code does not exist on the item, THEN the command SHALL exit with status 1 and write nothing.
Link kinds SHALL be ticket, mr, slack, doc, or report, and a url SHALL be http or https without spaces, the same rules the publish command applies, except that a report MAY omit the url.

#### Scenario: Reply terms replace
- **WHEN** an item has two reply terms and the command receives two other `--reply-term` values
- **THEN** the item holds only the two given terms
- Proven by `test_reply_terms_given_once_or_more_replace_the_whole_list`

#### Scenario: Reply terms clear
- **WHEN** the command receives `--clear-reply-terms`, or that flag with `--reply-term`
- **THEN** the first call leaves an empty list and the second exits with status 2 with the file unchanged
- Proven by `test_clear_reply_terms_sets_an_empty_list_and_conflicts_with_reply_term`

#### Scenario: Add links
- **WHEN** the command adds a slack link, a doc link, and a link whose code already exists
- **THEN** the item holds each code once and the repeated code carries the new url
- Proven by `test_add_link_accepts_slack_and_doc_and_replaces_a_link_with_the_same_code`

#### Scenario: Drop links
- **WHEN** the command drops an existing code, then drops a code the item lacks
- **THEN** the first call leaves an explicit empty links list and the second exits with status 1 with the file unchanged
- Proven by `test_drop_link_removes_by_code_and_an_unknown_code_is_an_error`

#### Scenario: Links the file omits
- **WHEN** the item has no links field and the last published revision holds links
- **THEN** an add or drop starts from the published links so a publish does not lose them
- Proven by `test_link_edits_start_from_the_last_published_links_when_the_file_has_none`

#### Scenario: Add a report path
- **WHEN** the command adds a report link whose code is a file path and that has no url, then adds a report link with a non-http url
- **THEN** the first link is stored with no url and the second call exits with status 2 with the file unchanged
- Proven by `test_add_link_accepts_a_report_path_with_no_url_and_checks_a_given_url`
