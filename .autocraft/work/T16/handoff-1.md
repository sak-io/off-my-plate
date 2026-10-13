# T16 developer handoff 1

```
HANDOFF
From: developer            To: pr-reviewer
Status: DONE
Summary: SpokenCommandParser (ADR 0012 grammar, approve -> .openApprovalSheet only) and SafetyTextParser
  (catalog keywords -> restriction candidates, .unmapped for everything else), plus 12 Malayalam keywords
  in catalog.json (owner sign-off needed). Safety-relevant: full review.
  Not compiled locally (no Swift toolchain); `scripts/check-core.sh --lint-only` OK. Every golden
  expectation was cross-checked with a Python port of both parsers (incl. IngredientResolver and the
  bundled catalog) plus a Python "never drops a word" fuzz.
Artifacts: local branch feat/t16 (based on 03e4b1d).
Next: lead merges into claude/build-v1 and pushes; CI (Linux + macOS) must be green; review.
```

## What (by AC)
- `Parsing/SpokenCommandParser.swift` (ADR 0012, G9, AC-9.4, AC-5.6)
  - `SpokenCommandParser(resolver:).parse(_:) -> SpokenCommandParseResult {commands, unparsed, wasTruncated}`.
  - `SpokenCommand`: `.add`, `.markOut`, `.remove` (each `[SpokenPantryItem]`) and `.openApprovalSheet`.
    There is **no approve case**: "approve", "approve it/the plan/this week", "looks good (to me)", "that looks
    good", "approved" only open the sheet (at most once per transcript). The confirming tap stays in the UI
    (T18's `approve(UserConfirmation)`).
  - Grammar: optional subject (I, we, I've, we're, I'm, just, also, please, ...) + verb: bought / got / picked
    up / add / added / purchased; out of / are (all) out of / ran|run out of / used up / finished / no more;
    remove / delete. Item lists split on `,` `and` `plus`, except the "and" inside "one and a half" and
    "two hundred and fifty". A new verb or `. ! ? ;` / new line ends a command.
  - Numbers: digits via T15's `QuantityLexicon` (`2`, `1.5`, `1/2`, `½`, `1 1/2`, `2kg`); words one to nineteen,
    twenty to ninety (+ ones), hundreds; `a/an` = 1; `half`, `a quarter`, `a couple`, `a pair`; `and a half`;
    `half a kilo`. **A dozen is a count of 12** (`qty 12, unit nil`; `quantity` = 12 pieces), so "a dozen eggs"
    shows "eggs 12" as AC-9.4 says. Units from T15's lexicon; pinch drops the amount.
  - `SpokenPantryItem {spokenText, name, qty?, unit?, match, isConfident}`: `match` is the resolver's best
    candidate; `isConfident` = T15 `confidentMatch`. An item whose name has **no** resolver candidate (e.g.
    "that stuff", "quinoa") is not guessed: its words go to `unparsed`. A command with no understood item
    returns the whole command ("I bought 2 kg") as unparsed. Filler-only pieces ("um, okay so") are dropped.
  - Cap: 2,000 characters (`wasTruncated`).
- `Parsing/SafetyTextParser.swift` (AC-2.3, AC-2.4, plan section 8)
  - `SafetyTextParser(keywords:)` takes the keyword table (`SeedCatalog.restrictionKeywords`), so OMPDomain
    does not depend on OMPRecipes. `parse(_:) -> [SafetyCandidate]`.
  - `SafetyCandidate`: `.restriction(id, matchedText:, memberHint:)` (one row per restriction: "nuts" ->
    peanuts + tree-nuts) and `.unmapped(text:, memberHint:)`.
  - Clauses split on punctuation and and/or/but/plus/also/nor/then. Keywords match longest first ("tree nut"
    beats "nut"), case-insensitive, with or without a plural ("almonds" -> almond). Known grammar words
    (`ignoredWords`: no, can't, have, allergy, my son, ...; Hindi "nahi", Malayalam "illa", "venda") are skipped.
  - **Never drop, never "safe":** every other run of words becomes `.unmapped`; a clause with no candidate at
    all (e.g. "nothing", "allergy") becomes `.unmapped(<whole clause>)`; text beyond the 2,000-character cap
    becomes one `.unmapped("<first 60 chars>…")`.
  - Member hints: "Meera has a nut allergy", "Meera's nut allergy", "Meera: no nuts", "no nuts for Meera" give
    `memberHint: "Meera"` on that clause's rows. A name is never a restriction. The hint is only taken when the
    rest of the clause maps at least one restriction; otherwise the name stays visible as `.unmapped`
    ("Meera has a kiwi allergy" -> `?Meera`, `?kiwi`), so an unknown food can never hide as a "name".
  - Duplicate rows: one per (restriction, hint); identical unmapped rows once.
- `OMPRecipes/Resources/seed/catalog.json` + `docs/content/seed-review.md` keyword table: **12 Malayalam
  keywords, need owner sign-off** (Q1).

## Tests
- `OMPDomainTests/SpokenCommandParserTests`: 73-transcript golden table (incl. "I bought 2 kg rice and a dozen
  eggs" -> rice 2 kg, eggs 12; Hindi/Malayalam names; multi-sentence; mixed add/out/remove/approve); AC-9.4
  detail test; unparsed remainder (order, as heard, whole-command case, fillers); 14 approve phrasings ->
  exactly `[.openApprovalSheet]`; exhaustive-switch tripwire + "at most one sheet request" over the table;
  number words; pinch; truncation; determinism.
- `OMPDomainTests/SafetyTextParserTests`: 49-answer golden table (spec examples, hints, unmapped, Hindi,
  Malayalam incl. script, hyphens, emoji, dedupe); empty keyword table -> all unmapped; keyword merge; overflow;
  "no golden answer drops a word" (every input word not in `ignoredWords`/keyword words appears in some row);
  no ignored word is a keyword.
- `OMPDomainTests/VoiceParserFuzzTests`: seeded fuzz (reuses T15 random Unicode generator + grammar fragments)
  for both parsers, 800 texts each + long inputs: no crash, invariants, determinism, and for safety text
  "never drops a word".
- `OMPRecipesTests/SafetyKeywordTests`: integration with the bundled catalog: every keyword maps exactly to
  its restrictions with no unmapped row; no keyword is an ignored word; spec examples; Malayalam keywords.

## Questions (recommended defaults implemented)
- Q1 **Owner sign-off: Malayalam keywords** added to the catalog: meen -> fish, mutta -> egg, kappalandi and
  nilakkadala -> peanuts, paal -> milk, chemmeen / konju / njandu -> shellfish, ellu -> sesame, kaduku ->
  mustard, gothambu -> wheat-gluten, andiparippu -> tree-nuts. Note "thenga paal" (coconut milk) also selects
  milk (over-restrictive, shown for confirmation; "thenga" comes back unmapped). Malayalam-script spellings
  were not added (normalisation of chillu letters needs a decision). `contentVersion` was **not** bumped
  (keywords do not change plans); bump to `2026.10.13-t16` if you want sign-off tracked by version.
- Q2 Suggested English keywords for the owner to approve later (not added): meat / non veg -> vegetarian;
  paneer, ghee, curd, dahi, butter, cheese, yogurt -> milk. Today they come back unmapped (safe).
- Q3 Negations like "eggs are fine" still map egg (over-restrictive, the user removes it on S-02). Detecting
  "fine/ok" was judged riskier than an extra row.
- Q4 "Meera and Ravi can't have nuts" splits on "and": "Meera" comes back unmapped (user removes), rules get no
  hint. Safe, slightly noisy.
- Q5 Voice "used 200 g rice" (partial use) is not in the ADR grammar; it comes back unparsed.
- Q6 Size: ~990 source + ~700 test lines, over the 400 guideline; the two parsers share no code, so they can be
  split into two reviews if preferred.
- Q7 `ignoredWords` and `clauseBreakWords` are public so the UI/tests can rely on them; no other new API.

## Self-check
- Swift 6: all new types Sendable; no locale APIs (`lowercased()` only); Foundation only.
- Signatures double-checked by reading; Python port mirrors control flow 1:1 (golden 73 + 49 cases, 5,000
  spoken and 3,000 safety fuzz inputs, all invariants held after fixing two issues it found: possessive "'s"
  after punctuation, and duplicate rows for "wheat/maida").
