# Restriction and keyword definitions: sign-off record (R4, G4)

The restriction table and keyword table in `seed-review.md` (what "vegetarian", "Jain", "wheat-gluten" and so on exclude, and which words select them) are a safety decision that only the owner, or a qualified reviewer they name, can approve. `scripts/release-readiness.sh` fails until the checkbox below is ticked with a reviewer and an ISO date.

Review the tables in `docs/content/seed-review.md` (sections "Restrictions" and "Keywords"), then edit the line below.

- [ ] Restriction and keyword definitions approved. Reviewer: ________ Date: ________

## App Store only (G4: legal/privacy and dietitian review; not needed for TestFlight beta)

- [ ] Privacy policy, data map and disclaimer wording approved. Reviewer: ________ Date: ________
- [ ] Recipe allergen tags spot-checked by a dietitian or food-safety reviewer. Reviewer: ________ Date: ________
