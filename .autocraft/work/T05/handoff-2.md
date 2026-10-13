# T05 handoff 2: review round 1 fixes + Kerala coverage

- **From:** developer -> **To:** pr-reviewer
- **Branch:** `feat/t05` (local). Responds to `review-1.md` and to owner input of 2026-10-13 (the household cooks mostly Kerala dishes).

## Review round 1
- [MAJOR] Shared-mill flours: **Fixed.** `besan`, `rice-flour`, `ragi-flour`, `jowar-flour`, `bajra-flour`, `maize-flour` and `cornflour` now have `mayContain: [wheat, gluten]`. Their tags stay empty and they stay verified. The pinned test is flipped: `sharedMillFlours` checks that the tags have no wheat/gluten and that `mayContain` has both.
- [MAJOR] Ready masalas: **Fixed.** `garam-masala`, `biryani-masala` and `tandoori-masala` now have `mayContain: [wheat, gluten, mustard, sesame]`. I added sesame to all three to be conservative. New test: `readyMasalas`.
- [MINOR] `malai`: **Confirmed.** It is already a synonym on `fresh-cream`.
- [MINOR] Chikki: **Added** `chikki`: tags peanut, mayContain sesame, unverified, aisle other.
- [MINOR] Noodles: **Fixed.** They now have mayContain sesame. Papad now has mayContain sesame + peanut. New test: `hiddenSesameAndPeanut`.
- **Recipes:** none of the 3 placeholder recipes uses a changed ingredient. Their `declaredTags` still equal the derived tags (checked by script).

## Kerala coverage (owner input)
- **New ingredients:**
  - `tapioca` (kappa; tagged `rootVegetable`), `raw-jackfruit` (chakka), `ash-gourd` (kumbalanga).
  - `red-cowpeas` (vanpayar), `matta-rice` (rosematta, kuthari).
  - `puttu-flour` (puttu podi) and `appam-batter` (fridge, 3 days): both unverified with mayContain wheat+gluten, following the shared-mill rule.
  - `malabar-tamarind` (kudampuli).
  - `sardine` (mathi), `mackerel` (ayala), `pearl-spot` (karimeen): all tagged `fish`.
- **Malayalam synonyms added to existing items:**
  - thenga, nalikeram (coconut); chirakiya thenga (grated coconut); velichenna (coconut oil).
  - thenga paal, thick/thin coconut milk, onnam/randam paal (coconut milk).
  - kariveppila (curry leaves); kunjulli and cheriya ulli (shallots); savala and valiya ulli (onion).
  - nendran (raw banana); chena (yam); chembu (colocasia); muringakka (drumstick); cherupayar (green gram).
  - pachari, raw rice, appam rice (rice); idiyappam/appam/pathiri podi (rice flour).
  - sharkara (jaggery); elakka (cardamom); ney meen (seer fish); konju (prawns); mutta (egg).
  - Already present: kadala (kala chana), meen (fish), desiccated coconut (dry coconut).
- **Correction:** `kudampuli` and `garcinia` were removed from `kokum`. Kudampuli is a different fruit (Garcinia gummi-gutta), so it is now its own entry. Kokum gains `punarpuli`.
- **Catalog:** new cuisine `kerala` (`cuisine.kerala`), placed after southIndian. **Follow-up for the lead/UX:** the onboarding cuisine picker (C-035b) and the localisation strings need the new label.
- **Left out:** beef, as instructed.
- **New test:** `keralaStaples` (25 Malayalam lookups, fish tags on the new fish, tapioca as a root vegetable, kerala cuisine present). puttu-flour and appam-batter are added to the unverified list.

## Owner decision recorded
- Coconut is not an allergen and not a tree nut. There is no coconut tag, and handoff-1 item 1 is marked as decided.

## Evidence
- Python mirror of the validator: OK, **184 ingredients**, all names and synonyms unique, recipes' declaredTags equal derived tags.
- `check-core.sh --lint-only`: OK.
- No Swift toolchain here, so the tests were not compiled or run locally. CI is the verification of record.
