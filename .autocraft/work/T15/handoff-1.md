# T15 developer handoff 1

```
HANDOFF
From: developer            To: pr-reviewer
Status: DONE
Summary: Notes parser, ingredient resolver, InboxImport v1 + file naming, share-input policy, with tests.
  Not compiled locally (no Swift toolchain); `scripts/check-core.sh --lint-only` OK. Resolver test
  expectations cross-checked with a Python port of the algorithm (incl. the bundled seed).
Artifacts: local branch feat/t15 (based on ac11631; build-v1 has moved on, no overlapping files).
Next: lead merges into claude/build-v1 and pushes; CI (Linux + macOS) must be green; review.
```

## What (by AC)
- `Parsing/ShoppingTextParser.swift` (AC-11.1, plan section 8): splits on any newline (CRLF, CR, U+2028);
  strips `-`, `*`, `+`, `•`, `◦`, `☐`, numbering `1.`/`2)`, `[ ]`/`[x]`; ticks `☑ ☒ ✓ ✔ ✅`, trailing ticks and
  `~~text~~` set `wasChecked` (R7: `isSelectedByDefault == false`). Shapes: `2 kg rice`, `rice - 2kg`, `rice 2kg`,
  `milk x2`, `2 x milk`, `1/2 kg`, `1 1/2 kg`, `½ kg`, `a dozen eggs`, `dozen eggs`, `eggs (12)`, `two onions`,
  `Eggs one dozen`, `2 kg of rice`. Output `{lineIndex, rawLine, name, qty?, unit?, wasChecked, confidence}`.
  Caps: 64 KB UTF-8 (cut on a character boundary) and 500 non-blank lines; `wasTruncated` reported.
  Numbers: ASCII digits only, at most 6 integer / 3 fraction digits, > 0 (huge or zero amounts stay text).
- `Parsing/QuantityLexicon.swift`: unit spellings (g/gm/kg/kilo/ml/l/ltr/tsp/tbsp/cup/dozen/pinch; pcs/nos/
  packet/pack/bunch -> piece), number words, vulgar fractions.
- `Parsing/IngredientResolver.swift` (AC-9.1, plan section 8): tiers exactName > exactSynonym > singularised >
  prefix > token > contains (>= 3 chars) > nearMiss (edit distance 1, >= 5 chars). Ties: length gap, name,
  id; independent of input order. `confidentMatch` only for a unique exact/plural match (never forced).
  Takes `[Ingredient]`; no OMPRecipes dependency.
- `Inbox/InboxImport.swift` (ADR 0011, AC-11.3 format): v1 `{schemaVersion, importId, createdAt, destination,
  items[{name, ingredientId?, quantity?, unit?}]}`; sorted keys, ISO 8601 whole seconds. `decode` reads
  `schemaVersion` first (unknown -> `.unsupportedSchemaVersion`), 256 KB cap, throws only `InboxImportError`
  (`malformed` / `invalid` / `fileTooLarge`) so the app can quarantine to `Inbox/failed/`.
- `Inbox/InboxFiles.swift`: `Inbox/<importId>.json`, `failed/`; `importID(fromFileName:)` rejects hidden/temp/
  path-escaping names (id = `[a-z0-9-]{1,64}`). `ShareInputPolicy` (AC-11.4): plain-text UTIs only.

## Tests
`ShoppingTextParserTests` (44-line golden Kerala/Malayalam fixture per line and as one note, R7, line endings,
caps), `ParserFuzzTests` (seeded random Unicode/fragments, 600 texts + over-cap texts; invariants, determinism;
resolver fuzz), `IngredientResolverTests` (tiers, Hindi/Malayalam incl. Malayalam script, ambiguity, order
independence), `InboxImportTests` (round trip, golden v1 bytes, versions 0/2/99/-1 rejected, malformed/invalid,
naming, share policy), `OMPRecipesTests/SeedResolverTests` (every name and unique synonym of the real seed
resolves; Kerala note end to end).

## Questions / deviations (recommended defaults implemented)
- Q1 Size: ~1090 source + ~710 test lines (over the 400 guideline); kept as one task since the three parts are
  one contract. Can split into parser / resolver / inbox if the reviewer prefers.
- Q2 Resolver order merges plan section 8 (synonym -> singular -> token -> edit distance) with the brief
  (exact name, synonym, prefix, contains); prefix/contains were added for the picker type-ahead.
- Q3 "Unsure" heuristic (S-40 "Not sure about these"): no letters, quantity only, ends with `:`/`?`, links,
  > 80 chars, > 5 words without a quantity, or to-do cue words (call, pay, today, re, ...). The app should also
  treat rows with no resolver candidate as unsure.
- Q4 Packs/bunches count as pieces; a count without a unit ("milk x2") has `unit == nil`.
- Q5 `rice-2kg` (no spaces) is not split; it stays a name.
