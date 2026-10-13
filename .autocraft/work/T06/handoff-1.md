# T06 handoff 1: 30 seed recipes (mostly Kerala)

- **From:** developer -> **To:** pr-reviewer (then the owner signs off each recipe's tags, G1)
- **Branch:** `feat/t06` (local worktree, based on `claude/build-v1` @ fab1aa0; not pushed)
- **Task:** T06; spec A2, A3, AC-4.3, G1, G5. Content task. It is safety-relevant because the planner trusts `declaredTags`/derived tags.

## What
- `Packages/Core/Sources/OMPRecipes/Resources/seed/recipes.json`: replaced the 3 T04 placeholders (dal tadka, kanda poha, jeera rice) with **30 original recipes** written in our own words. Every recipe serves 4, has `provenance.source = "original (OffMyPlate team)"` and `review.status = "draft"`. 26 are `kerala` and 4 are `southIndian` (lemon, curd, tomato and coconut rice).
- No new ingredients. All lines use T05 ids. To keep recipes available to households with a hard rule (AC-4.3), I avoided unverified ingredients:
  - coconut milk is squeezed from `grated-coconut` (verified), not taken from the unverified `coconut-milk`;
  - puttu and idiyappam use `rice-flour`, not the unverified `puttu-flour`;
  - appam is made from soaked `rice` + `grated-coconut` + `baking-soda`, not the unverified `appam-batter`;
  - spices are added individually, with no ready masala blends.

  **Only `kerala-rasam` uses an unverified ingredient (hing).** A test pins this.
- `declaredTags` are generated from `ingredients.json` (tags plus mayContain over every line, including optional lines), so they equal the derived tags by construction. The python validator mirror (below) confirms it.
- `contentVersion` is bumped to `2026.10.13-t06` in all three seed files.
- `docs/content/seed-review.md`: the sign-off sheet (885 lines).
- Tests: new `Packages/Core/Tests/OMPRecipesTests/SeedContentTests.swift`. No existing test pinned the old placeholder recipes: the `dal-tadka` references in `SeedValidatorTests`, `ReviewSheetTests` and OMPDomain are fixture/sample ids, not bundled content. So nothing else needed to change.

## Recipes
| Title | id | Meals | Region | Derived tags |
|---|---|---|---|---|
| Appam with vegetable stew | `appam-vegetable-stew` | breakfast, dinner | kerala | rootVegetable, onion |
| Puttu with kadala curry | `puttu-kadala-curry` | breakfast | kerala | wheat, gluten, mustard, rootVegetable, onion, garlic |
| Puttu with banana | `puttu-pazham` | breakfast | kerala | wheat, gluten |
| Idiyappam with egg curry | `idiyappam-egg-curry` | breakfast, dinner | kerala | egg, wheat, gluten, rootVegetable, onion, garlic |
| Dosa with coconut chammanthi | `dosa-coconut-chammanthi` | breakfast | kerala | rootVegetable, onion |
| Idli with plain coconut chutney | `idli-coconut-chutney` | breakfast | kerala | mustard |
| Rava upma with vegetables | `rava-upma` | breakfast | kerala | wheat, gluten, mustard, rootVegetable, onion |
| Chapati with green peas curry | `chapati-green-peas-curry` | breakfast, dinner | kerala | wheat, gluten, rootVegetable, onion, garlic |
| Varutharacha sambar with matta rice | `varutharacha-sambar` | lunch, dinner | kerala | mustard, onion |
| Kerala rasam with rice | `kerala-rasam` | lunch, dinner | kerala | wheat, gluten, mustard, garlic (hing unverified) |
| Avial with matta rice | `avial` | lunch, dinner | kerala | milk, rootVegetable |
| Cabbage thoran with matta rice | `cabbage-thoran` | lunch, dinner | kerala | mustard, onion, garlic |
| Olan with matta rice | `olan` | lunch, dinner | kerala | none |
| Kalan with matta rice | `kalan` | lunch, dinner | kerala | milk, mustard |
| Mathanga erissery with matta rice | `mathanga-erissery` | lunch, dinner | kerala | mustard |
| Vellarikka pulissery with matta rice | `vellarikka-pulissery` | lunch, dinner | kerala | milk, mustard |
| Parippu curry with rice and ghee | `parippu-curry` | lunch, dinner | kerala | milk, mustard, onion, garlic |
| Mathi curry with matta rice | `mathi-curry` | lunch, dinner | kerala | fish, rootVegetable, onion, garlic |
| Karimeen pollichathu with matta rice | `karimeen-pollichathu` | lunch, dinner | kerala | fish, rootVegetable, onion, garlic |
| Kappa with ayala curry | `kappa-ayala-curry` | lunch, dinner | kerala | fish, rootVegetable, onion, garlic |
| Nadan chicken curry with matta rice | `nadan-chicken-curry` | lunch, dinner | kerala | poultry, rootVegetable, onion, garlic |
| Chemmeen curry with matta rice | `chemmeen-curry` | lunch, dinner | kerala | shellfish, rootVegetable, onion |
| Lemon rice | `lemon-rice` | lunch + lunchbox | southIndian | mustard |
| Curd rice | `curd-rice` | lunch + lunchbox | southIndian | milk, mustard |
| Tomato rice | `tomato-rice` | lunch + lunchbox | southIndian | rootVegetable, onion, garlic |
| Neychoru (Kerala ghee rice) | `neychoru` | lunch, dinner + lunchbox | kerala | treeNut, milk, onion |
| Chapati with Kerala egg roast | `chapati-egg-roast` | lunch, dinner + lunchbox | kerala | egg, wheat, gluten, rootVegetable, onion, garlic |
| Chapati with vegetable kurma | `chapati-vegetable-kurma` | lunch, dinner + lunchbox | kerala | wheat, gluten, rootVegetable, onion, garlic |
| Beans thoran with matta rice | `beans-thoran-rice` | lunch + lunchbox | kerala | mustard, rootVegetable, onion, garlic |
| Coconut rice | `coconut-rice` | lunch + lunchbox | southIndian | none |

**Split** (the test pins these counts and checks that the groups do not overlap):
- 8 breakfast: the recipes with `breakfast` in `mealTypes`.
- 14 lunch/dinner mains: lunch or dinner, not breakfast, not lunchbox.
- 8 lunchbox: `lunchboxSuitable` true. Each of these is also a lunch, and three are also dinner.

## Coverage (recipes allowed per slot; planner semantics: no excluded tag AND no unverified ingredient)
| Restriction | Breakfast | Lunch | Dinner | Lunchbox |
|---|---|---|---|---|
| peanuts | 8 | 21 | 19 | 8 |
| tree-nuts | 8 | 20 | 18 | 7 |
| milk | 8 | 15 | 14 | 6 |
| egg | 7 | 20 | 17 | 7 |
| wheat-gluten | 3 | 19 | 15 | 6 |
| soy | 8 | 21 | 19 | 8 |
| sesame | 8 | 21 | 19 | 8 |
| mustard | 5 | 12 | 13 | 5 |
| fish | 8 | 18 | 16 | 8 |
| shellfish | 8 | 20 | 18 | 8 |
| beef | 8 | 21 | 19 | 8 |
| pork | 8 | 21 | 19 | 8 |
| vegetarian | 7 | 15 | 12 | 7 |
| jain | 2 | 7 | 4 | 3 |
| **vegetarian + Jain + peanuts + tree nuts** | **2** | **7** | **4** | **3** |

- Every **pair** of chips also leaves at least 1 recipe in every slot. The only pair gap during drafting was Jain + mustard in the lunchbox. I closed it by tempering coconut rice with cumin instead of mustard.
- Tests: `everyRestrictionCoversEverySlot`, `everyRestrictionPairCoversEverySlot` and `vegetarianJainNutHousehold`. The last one pins `[2, 7, 4, 3]`. `knownGaps` is empty; a future gap has to be listed there, which reports it to the owner.

## Known gaps / risks
1. **Snack slot: 0 recipes** (G5 default: snacks off by default). A test (`noSnacks`) documents this. If the owner turns snacks on, we need snack content.
2. **Thin choice for Jain households:** breakfast has only 2 recipes (puttu with banana, idli with chutney) and dinner has 4. With "no repeat within 3 days", the variety rule will relax for these households (G5 default behaviour).
3. **Wheat/gluten breakfast is 3 recipes** (appam, dosa, idli). Puttu and idiyappam drop out because T05 tags rice flour as may-contain wheat/gluten.
4. **Three-way combinations** (for example Jain + mustard + wheat) are not tested. A Jain + mustard-free + wheat-free lunchbox has only coconut rice.
5. **Review sheet produced without Swift.** No Swift toolchain was available, so I wrote a Python reproduction of `SeedReviewSheet.markdown(for:)` (in my scratchpad, not committed) and checked it byte-for-byte against the `ReviewSheetTests` golden fixture output (match). CI's golden test only covers the fixture library, not this file, so `docs/content/seed-review.md` could drift from the Swift output in ways the fixture does not exercise. The likeliest place is number formatting, e.g. `0.25` and `1.25`, which Swift's `String(Double)` should print the same way. **Recommended:** the lead (or macOS CI) runs `swift run --package-path Packages/Core seed-review-sheet docs/content/seed-review.md` once and commits any diff. A follow-up could add a test that compares the bundled sheet with the committed file.
6. **Validation done with a Python mirror** of SeedValidator's rules: header and versions, ids, regions, meal types, numbers, steps, dangling ids, unit dimension and convertibility using gramsPerMl/gramsPerPiece, quantity > 0 for quantified units, declared == derived, provenance, review. Result: OK. The Swift tests have **not been run locally**, so CI is the verification of record. `bash scripts/check-core.sh --lint-only` passes.
7. Banana leaf for pollichathu is mentioned in a step ("or foil") but is not an ingredient line, so it will not appear on the shopping list.

## Owner sign-off notes (G1)
- **Hing deliberately omitted** from the sambar, lemon rice and curd rice. Compounded hing is unverified and may contain wheat, so it would hide those dishes from every household with a hard rule. The rasam keeps it, and its provenance note says so. Decide whether you want hing back in any of them.
- **Coconut** carries no tag (your decision in T05). Olan and coconut rice therefore have no tags at all.
- **Neychoru:** the cashews and raisins are *optional* lines, but they still make the dish tree-nut for safety checks (optional lines count). Choose: keep them, or drop them so ghee rice is nut-free.
- **Kalan** uses raw banana only (no yam), and **erissery/pulissery/olan** have no shallots or garlic, so they suit Jain households. Add yam or shallots if you prefer the traditional versions; they will then drop out of Jain plans.
- **Coconut rice** is tempered with cumin instead of mustard so mustard-free Jain lunchboxes have an option.
- **Curd rice** includes half a cup of milk, which keeps it from souring before lunch.
- **Appam** ferments overnight with baking soda instead of yeast or toddy, because there is no yeast ingredient in the taxonomy.
- Quantities are home-style estimates for 4 servings. Please check portions, especially rice (300 g raw for 4 people) and fish (500 g sardines; 4 pearl spot; 4 mackerel).
- Every recipe is `draft`. Signing off means setting `review.status: signedOff` with `reviewer` and `reviewedOn` in `recipes.json` and ticking the box in the sheet.

```
HANDOFF
From: developer            To: pr-reviewer
Status: DONE
Summary: 30 original seed recipes (26 Kerala, 4 South Indian; 8 breakfast / 14 mains / 8 lunchbox), all draft, declaredTags derived from T05 tags. Every restriction chip and every pair of chips leaves at least 1 recipe per slot; the veg + Jain + nuts household has 2/7/4/3. Sign-off sheet generated by a Python mirror of SeedReviewSheet; Swift tests not run locally.
Artifacts: Packages/Core/Sources/OMPRecipes/Resources/seed/{recipes,catalog,ingredients}.json, docs/content/seed-review.md, Packages/Core/Tests/OMPRecipesTests/SeedContentTests.swift
Open items: 1. Regenerate seed-review.md with the Swift executable and diff it. 2. Owner sign-off of tags and the judgement calls above. 3. Snack content if snacks get enabled.
Next: review the recipes and tags against ingredients.json, and let CI run the Swift tests on both platforms.
```
