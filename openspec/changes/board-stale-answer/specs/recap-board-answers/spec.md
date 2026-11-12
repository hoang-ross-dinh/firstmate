## MODIFIED Requirements

### Requirement: Last response shows the newest answer
The panel SHALL show a Last response section that holds the task's newest answer from any revision, unless a later revision changed the summary.
Test: `tests/fm-recap-publish.test.sh` - test_the_last_response_keeps_the_answer_after_a_publish_that_omits_it

#### Scenario: Answer kept
- **WHEN** iteration 4 stored an answer for task "a" and iteration 5 changed "a" without an answer and without changing its summary
- **THEN** the Last response section of "a" shows the iteration 4 answer

## ADDED Requirements

### Requirement: Stale answer hides the section
WHEN a revision newer than the newest answer holds a different summary from the revision that stored the answer, the panel SHALL hide the Last response section.
The section SHALL stay hidden when a comment reply exists, because a reply has no time to compare with the summary change.
History and the comment list SHALL still show the answer and the replies.
WHEN a publish changes the summary and sends an answer together, the panel SHALL show that answer.
Test: `tests/fm-recap-publish.test.sh` - test_the_last_response_hides_an_answer_the_summary_has_moved_past
Test: `tests/fm-recap-publish.test.sh` - test_a_stale_answer_does_not_fall_back_to_an_older_comment_reply

#### Scenario: Summary moved on
- **WHEN** iteration 4 stored an answer for task "a" and iteration 5 changed the summary of "a"
- **THEN** the panel of "a" has no Last response section and History still lists the answer

#### Scenario: Answer sent with the change
- **WHEN** iteration 6 changes the summary of "a" and sends an answer in the same publish
- **THEN** the Last response section shows the iteration 6 answer
