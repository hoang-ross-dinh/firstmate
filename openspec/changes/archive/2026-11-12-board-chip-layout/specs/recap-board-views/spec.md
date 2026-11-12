## ADDED Requirements

### Requirement: Header never covers the first filter chip
WHILE the viewport is 1024 px wide or narrower, the board SHALL let the page header scroll away with the list, so that no header control paints over the first filter chip.
Test: `tests/fm-recap-publish.test.sh` - test_the_nav_never_paints_over_the_first_filter_chip_at_compact_widths

#### Scenario: Scrolling the list at a compact width
- **WHEN** the captain scrolls the list at a viewport 600 px wide, where the header wraps onto two rows
- **THEN** no opaque header surface is over the text of the first filter chip at any scroll position
