# T16 developer handoff 2 (macOS fuzz failure)

Cause: the PARSER was wrong, not just the test helper. Swift groups " " + combining mark into one
`Character` whose first scalar is whitespace. `Character.isWhitespace` splitting therefore swallowed
the mark and hid word boundaries (e.g. "no" + space + mark + "nuts"). Benign here, but text could
vanish without surfacing (AC-2.4).

Fix: new public `TranscriptSanitiser.sanitise` (Parsing/TranscriptSanitiser.swift) replaces
"orphan" extenders (marks, ZWJ/ZWNJ, emoji modifiers, tag chars not following a letter/number) with
U+FFFD, a standalone non-letter. Both `SafetyTextParser.parse` and `SpokenCommandParser.parse` sanitise
first (before the length cap). Marks after letters (Malayalam/Devanagari) are kept. The test helper
`droppedWords` sanitises the same way.

Tests: regression strings from the CI report (+ extras) in `SafetyTextParserTests.orphanMarks`,
sanitiser unit test, spoken regression. Not compiled locally; lint OK. Linux result pending.
