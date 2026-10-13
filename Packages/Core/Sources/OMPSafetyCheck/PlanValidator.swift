import OMPDomain

/// The independent hard-rule plan validator (ADR 0007; AC-4.2, AC-4.3, AC-6.3).
///
/// A separate code path from the planner: it recomputes every recipe's tags from the raw
/// ingredient lines and the ingredient taxonomy, and never reads `Recipe.declaredTags` or the
/// planner's tag index. `OMPServices` calls it before a draft is displayed and inside `approve`.
///
/// Rules, per meal that has a recipe, for every eater (every active household member and every
/// serving's member, except members with only `notEating` servings; see `eaterIDs`):
/// - the hard rules covering the eater are their member-scope rules plus every household-scope
///   rule (`Household.rules(covering:)`);
/// - an ingredient whose `tags` or `mayContain` intersect those rules' excluded tags is an
///   `.excludedTag` violation, one per (ingredient, tag); optional lines count too;
/// - an unverified ingredient is an `.unverifiedIngredient` violation when the eater has at
///   least one hard rule (AC-4.3);
/// - fail closed: a recipe missing from the library is `.unknownRecipe`, and a line whose
///   ingredient is missing from the taxonomy is `.unknownIngredient`, for every eater whether
///   or not they have rules, because nothing is known about what they would eat.
///
/// Members explicitly marked not eating are ignored (AC-6.3); a member merely missing from
/// `servings` is still checked (fail closed). Empty meals have nothing to check.
public enum PlanValidator {
    /// Validates `plan` against `household`'s hard rules using `library`'s raw data.
    ///
    /// Violations are ordered deterministically: by meal (plan order), then eater (serving
    /// order, then remaining active members in household order), then ingredient line order, then tag in
    /// `FoodTag.allCases` order. A repeated ingredient line or eater is reported once.
    /// The report carries `plan.contentHash`, so it only approves this exact content (ADR 0008).
    public static func validate(
        _ plan: MealPlan, household: Household, library: SafetyCheckLibrary
    ) -> ValidationReport {
        var violations: [Violation] = []
        for meal in plan.meals {
            violations.append(contentsOf: violationsIn(meal, household: household, library: library))
        }
        return ValidationReport(planId: plan.id, contentHash: plan.contentHash, violations: violations)
    }

    /// Who eats `meal`, fail closed: every active household member plus every serving's member,
    /// minus members whose only servings are explicit `notEating` ones (an eating serving beats a
    /// duplicate `notEating` one). An active member missing from `servings` is therefore checked.
    /// Order: serving order, then the remaining active members in household order.
    private static func eaterIDs(of meal: PlannedMeal, household: Household) -> [MemberID] {
        var eating = Set<MemberID>()
        var notEating = Set<MemberID>()
        for serving in meal.servings {
            if serving.notEating {
                notEating.insert(serving.memberId)
            } else {
                eating.insert(serving.memberId)
            }
        }
        let optedOut = notEating.subtracting(eating)

        var candidates: [MemberID] = meal.servings.map(\.memberId)
        candidates.append(contentsOf: household.activeMembers.map(\.id))

        var eaters: [MemberID] = []
        var seen = Set<MemberID>()
        for id in candidates where !optedOut.contains(id) && seen.insert(id).inserted {
            eaters.append(id)
        }
        return eaters
    }

    private static func violationsIn(
        _ meal: PlannedMeal, household: Household, library: SafetyCheckLibrary
    ) -> [Violation] {
        guard let recipeId = meal.recipeId else { return [] }

        let eaters = eaterIDs(of: meal, household: household)
        guard !eaters.isEmpty else { return [] }

        guard let lineIDs = library.recipeLines[recipeId] else {
            return eaters.map { Violation(mealId: meal.id, memberId: $0, kind: .unknownRecipe(recipeId)) }
        }

        var ingredientIDs: [IngredientID] = []
        var seenIngredients = Set<IngredientID>()
        for id in lineIDs where seenIngredients.insert(id).inserted {
            ingredientIDs.append(id)
        }

        var violations: [Violation] = []
        for eater in eaters {
            let hardRules = household.rules(covering: eater).filter { $0.kind == .hard }
            var excluded = Set<FoodTag>()
            for rule in hardRules {
                excluded.formUnion(rule.excludedTags)
            }
            let hasHardRule = !hardRules.isEmpty

            for ingredientID in ingredientIDs {
                guard let facts = library.ingredientFacts[ingredientID] else {
                    violations.append(
                        Violation(mealId: meal.id, memberId: eater, kind: .unknownIngredient(ingredientID)))
                    continue
                }
                if hasHardRule && facts.isUnverified {
                    violations.append(
                        Violation(mealId: meal.id, memberId: eater, kind: .unverifiedIngredient(ingredientID)))
                }
                let hits = facts.containedTags.intersection(excluded)
                for tag in FoodTag.allCases where hits.contains(tag) {
                    violations.append(
                        Violation(
                            mealId: meal.id, memberId: eater, kind: .excludedTag(tag, ingredient: ingredientID)))
                }
            }
        }
        return violations
    }
}
