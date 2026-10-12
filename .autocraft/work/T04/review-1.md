# T04 review, round 1: CHANGES REQUESTED

Safety logic correct: derived tags include mayContain and optional lines; unverified handled conservatively; R4 catalog correct and complete; validator gates library construction. Golden sheet checked line by line. D1–D5 accepted (D2: unknown keyword must never mean "no restriction").

- [MAJOR] BundledSeedTests.swift:59-72: pin exact excludedTags for all 14 chips in a table test; extend nutsKeyword to "nut"; assert every keyword resolves to ≥1 restriction.
- [MINOR] SeedValidator.swift:480,518-534: reuse T07 ConversionProfile.canConvert for quantified lines. Lead decision: an unquantified ingredient defaultUnit is allowed only if every line using it is unquantified.
- [MINOR] Add defect tests: restriction with empty/missing excludedTags; restriction with an unknown tag.
- [NIT] SeedReviewSheet.swift:38: match AC-4.3 wording; update golden.
- [NIT] SeedLibrary.swift:99: assert/comment the invariant instead of silently skipping unresolved lines.
- [QUESTION] Hindi keywords (anda, machli, gehun, doodh/paneer/ghee) and coconut vs tree nut → T05 content + owner G1 sign-off.
