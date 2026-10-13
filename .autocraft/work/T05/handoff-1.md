# T05 handoff 1: Ingredient taxonomy (~150 Indian home-cooking ingredients)

- **From:** developer -> **To:** pr-reviewer (then owner sign-off of the judgement calls below, G1)
- **Branch:** `feat/t05` (local worktree, based on `claude/build-v1` @ c0e9425)
- **Task:** T05; spec A3, A5, AC-4.3, AC-10.3, G1. Safety-relevant content task.

## What
- `Resources/seed/ingredients.json`: replaced the 16-item placeholder with **172 ingredients**. Each has synonyms/transliterations (Hindi plus common Tamil/Telugu/Kannada/Marathi/Bengali names), `tags`, `mayContain`, `tagStatus`, catalog `aisle`, `defaultUnit`, `gramsPerMl` / `gramsPerPiece` where a recipe is likely to need a conversion, `defaultLocation`, and `fridgeShelfLifeDays` for every fridge item (and only those).
- All 16 previous ids are kept, so the 3 placeholder recipes still resolve. Their `declaredTags` did not need to change.
- `catalog.json` `restrictionKeywords`: added `anda`, `ande` -> egg; `machli`, `machhi`, `machhli` -> fish; `gehun`, `gehu` -> wheat-gluten; `doodh`, `dudh` -> milk. `moongphali` -> peanuts was already there.
- `contentVersion` bumped to `2026.10.13-t05` in all three files (the validator requires them to match).
- Tests:
  - New `Tests/OMPRecipesTests/IngredientTaxonomyTests.swift`: a full validator pass on the bundled seed with at least 150 ingredients; every name and synonym unique (case-insensitive) across the taxonomy; 25 transliteration lookups; pinned hidden-allergen facts (hing, dairy -> milk, besan and rice flour wheat-free and verified, wheat products, soy sauce soy+wheat+gluten and unverified, oats may contain gluten, coconut is not a tree nut, oils carry their source allergen, nuts/seeds/soy, packaged items unverified, hing-containing blends and papad may contain wheat+gluten, Jain tags including ketchup may contain onion+garlic, vegetarian tags); only hing and saffron default to an unquantified unit; fridge shelf-life rule.
  - `BundledSeedTests`: a new `hindiKeywords` test. No existing exact table changed, because none of them pins the keyword map.

## Owner sign-off items (judgement calls; G1 "team drafts, owner signs off")
1. **Coconut is not a tree nut.** Coconut, grated coconut, dry coconut, coconut milk and coconut oil carry no allergen tag. A tree-nut-allergic member will see coconut recipes. Option: tag `treeNut` (or add it to `mayContain`) if you want the conservative route.
2. **Besan, rice flour and millet flours (ragi, jowar, bajra, maize) are verified wheat/gluten-free.** In India these are often ground in shared chakkis with wheat. Option: add `mayContain: [wheat, gluten]` to some or all of them. This would remove most gluten-free roti options for coeliac members. Besan is pinned as wheat-free in the tests, per the lead's brief.
3. **Oats:** `mayContain: [gluten]` only (per the brief), not `wheat`. The wheat-gluten chip excludes it either way.
4. **Cornflour (cornstarch) is verified with no tags.**
5. **Unverified (excluded for anyone with any hard rule, AC-4.3):** hing, every ready masala (garam, chaat, sambar, rasam, pav bhaji, chole, biryani, tandoori), processed cheese, instant noodles, bread, pav, rusk, baking powder, fruit salt (Eno), vinegar, ketchup, tomato puree, soy sauce, green chilli sauce, coconut milk, papad, mango pickle, sev, rose water.
6. **`mayContain` choices on packaged items:**
   - Sambar, rasam, chaat, pav bhaji and chole masala, and papad: wheat + gluten (they usually contain compounded hing). Garam, biryani and tandoori masala: none beyond unverified.
   - Vinegar: wheat + gluten (malt vinegar). Baking powder: wheat + gluten (starch filler).
   - Ketchup and tomato puree: onion + garlic (for Jain users).
   - Green chilli sauce: onion, garlic, wheat, gluten, soy.
   - Bread, pav and rusk: tags wheat + gluten; may contain milk, egg, soy, sesame.
   - Noodles: may contain egg and soy. Sev: may contain peanut, wheat, gluten.
   - Mango pickle (and the generic synonyms `achar` / `pickle`): tagged mustard; may contain garlic, onion, sesame.
7. **Raisins and dates: `mayContain: [treeNut]`** (they are usually sold and packed alongside nuts). **Chironji: tagged `treeNut`** (a seed, but treated as a nut by caution). **Makhana (fox nut): no tags**, because it is a lotus seed.
8. **Oils:** groundnut oil is tagged `peanut` even though refined peanut oil is often tolerated. Sesame oil is tagged `sesame` and mustard oil `mustard`. Mustard greens (sarson ka saag) are also tagged `mustard`.
9. **Jain:** fresh ginger, potato, sweet potato, carrot, radish, beetroot, colocasia and yam are tagged `rootVegetable`. Dry ginger powder (saunth) and turmeric powder are **not** tagged; many Jains accept dried forms. The taxonomy cannot express Jain avoidance of brinjal, honey or many-seeded vegetables: no tag exists for them, and honey is deliberately left out of the taxonomy.
10. **Meat:** mutton and keema (goat) are tagged `otherMeat`. Beef and pork ingredients are not included in v1.
11. **Fenugreek:** not tagged. It is a legume with reported peanut cross-reactivity, but there is no matching chip.
12. **Synonym choices:** ambiguous bare words are left out (`dhania`, `chana`, `mirch`, `kadalai`, `beans`, `cooking oil`, `refined oil`). The previous placeholder's `cooking oil` / `refined oil` synonyms for sunflower oil were **removed**, because a user might mean groundnut oil. `chawal` moved from basmati to a new generic `rice` entry. `gobi` means cauliflower.
13. **Units:**
    - Only hing and saffron default to `pinch`.
    - Curry leaves changed from `toTaste` to `g`, so they can appear on a shopping list. The existing `toTaste` recipe line stays valid.
    - Garlic and ginger have no `gramsPerPiece` (a "piece" could mean a clove or a bulb, or an inch or a knob), so recipes should use grams.
    - Densities and piece weights are typical household values, not lab measurements.
14. **Extra keywords** beyond the brief: `ande`, `machhli`, `gehu` and `dudh` (common spelling variants).
15. **Shelf lives** are conservative household estimates: fish/prawns/keema 1 day, chicken/mutton 2, milk 3, leafy greens 3-5, eggs 21. Green peas default to the freezer.

## Evidence
- A Python mirror of the validator's key rules was run on the bundled files: unique ids, unique names and synonyms, known tags/aisles/units/locations/statuses, positive numbers, units convertible for every recipe line, and `declaredTags` equal to the derived tags for all 3 recipes. Result: OK, 172 ingredients. The pinned test facts were cross-checked against the JSON with the same script.
- `bash scripts/check-core.sh --lint-only`: OK.
- No Swift toolchain here, so **build and tests were not run locally**. CI (Linux and macOS) is the verification of record.

## Risks
- The new tests were not compiled locally. They use only existing public API (`SeedLoader`, `SeedLibrary.ingredient(_:)`, `Ingredient`, `MeasureUnit.dimension`, `SeedCatalog.restrictions(forKeyword:)`).
- The allergen data is a team draft. It must not ship until the owner signs off the items above (G1).
