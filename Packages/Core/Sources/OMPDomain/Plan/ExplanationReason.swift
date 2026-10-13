/// Why the planner chose a recipe (AC-4.7; plan section 12a #8).
///
/// One case per positive score component, plus the variety-relaxation note. The core never
/// builds the sentence: the UI maps each case to a C-084 template in the String Catalog,
/// for example `.usesYourIngredient` -> "Uses your {ingredient}".
public enum ExplanationReason: Codable, Sendable, Hashable {
    /// Pantry coverage: "Uses your {ingredient}".
    case usesYourIngredient(IngredientID)
    /// A pantry item expires soon: "Uses your {ingredient}" (expiry variant).
    case usesExpiringIngredient(IngredientID)
    /// Weekday dinner within the time budget: "Quick weekday {meal}".
    case quickWeekday(MealSlot)
    /// Lunchbox slot: "Good for lunchboxes".
    case goodForLunchboxes
    /// Variety: "Something different from yesterday".
    case differentFromYesterday
    /// Favourite or frequently cooked: "You cook this often".
    case cookedOften
    /// Cuisine affinity from Facts.
    case cuisineYouLike(CuisineID)
    /// The 3-day variety rule had to be relaxed because too few safe recipes remain (G5).
    case repeatedFewSafeOptions
    /// The meal was locked, but its recipe is no longer safe for the people eating it (a hard
    /// rule changed), so regenerate replaced it and unlocked it. Always first in `reasons`.
    case lockedMealNoLongerSafe
}
