import Foundation
import OMPDomain

/// Renders the markdown sign-off sheet for the seed library (ADR 0010, G1): the restriction
/// definitions (R4), then every recipe with its ingredients, their tags and tag status.
///
/// The output is deterministic (file order, `FoodTag.allCases` order, keywords sorted) and
/// contains no dates, so it can be golden-tested and diffed between content versions.
/// The `seed-review-sheet` executable prints it.
public enum SeedReviewSheet {
    public static func markdown(for library: SeedLibrary) -> String {
        let recipes = library.recipes
        let signedOff = recipes.filter { $0.review.status == .signedOff }.count
        let unverified = library.ingredients.filter { $0.tagStatus == .unverified }.count
        let draft = recipes.count - signedOff
        var lines: [String] = ["# OffMyPlate seed review sheet", ""]
        lines.append("Content version: \(library.contentVersion) (schema \(SeedValidator.supportedSchemaVersion))")
        lines.append("Recipes: \(recipes.count) (signed off: \(signedOff), draft: \(draft))")
        lines.append("Ingredients: \(library.ingredients.count) (unverified: \(unverified))")
        lines.append("")
        lines.append(caveat)
        lines += ["", "## Restrictions", "", "| Restriction | Excludes |", "|---|---|"]
        for restriction in library.catalog.restrictions {
            lines.append("| `\(restriction.id)` | \(tagList(restriction.excludedTags)) |")
        }
        lines += ["", "## Keywords", "", "| Keyword | Selects |", "|---|---|"]
        for keyword in library.catalog.restrictionKeywords.keys.sorted() {
            let targets = (library.catalog.restrictionKeywords[keyword] ?? []).map { "`\($0)`" }
            lines.append("| \(cell(keyword)) | \(targets.joined(separator: ", ")) |")
        }
        lines += ["", "## Recipes"]
        for recipe in recipes {
            lines += recipeSection(recipe, library)
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static let caveat =
        "\"May contain\" tags count as \"contains\" in every safety check. A recipe with an unverified ingredient is never planned for anyone who has a hard rule."

    private static func recipeSection(_ recipe: Recipe, _ library: SeedLibrary) -> [String] {
        let meals = MealType.allCases.filter { recipe.mealTypes.contains($0) }.map(\.rawValue)
        var provenance = "- Provenance: \(cell(recipe.provenance.source))"
        if let notes = recipe.provenance.notes {
            provenance += " (\(cell(notes)))"
        }
        var review = "- Review: \(recipe.review.status.rawValue)"
        if let reviewer = recipe.review.reviewer {
            review += " by \(cell(reviewer))"
        }
        if let date = recipe.review.reviewedOn {
            review += " on \(date.isoString)"
        }
        let unverified = library.unverifiedIngredients(of: recipe).map { "`\($0.id)`" }
        let lunchbox = recipe.lunchboxSuitable ? "yes" : "no"
        let mealList = meals.joined(separator: ", ")
        let unverifiedList = unverified.isEmpty ? "none" : unverified.joined(separator: ", ")
        var lines: [String] = ["", "### \(cell(recipe.title)) (`\(recipe.id)`)", ""]
        var summary = "- Region: `\(recipe.region)`; meals: \(mealList); lunchbox: \(lunchbox); "
        summary += "serves \(recipe.servings); \(recipe.prepMinutes) + \(recipe.cookMinutes) min"
        lines.append(summary)
        lines.append(provenance)
        lines.append(review)
        lines.append("- Derived tags: \(tagList(library.derivedTags(of: recipe)))")
        lines.append("- Unverified ingredients: \(unverifiedList)")
        lines += ["", "| Ingredient | Amount | Contains | May contain | Status |", "|---|---|---|---|---|"]
        for line in recipe.ingredients {
            let ingredient = library.ingredient(line.ingredientId)
            let name = ingredient.map { cell($0.name) } ?? "?"
            let contains = ingredient.map { tagList($0.tags) } ?? "?"
            let mayContain = ingredient.map { tagList($0.mayContain) } ?? "?"
            let status = ingredient?.tagStatus.rawValue ?? "?"
            lines.append(
                "| \(name) (`\(line.ingredientId)`) | \(amount(line)) | \(contains) | \(mayContain) | \(status) |")
        }
        lines += ["", "- [ ] Ingredients and tags checked. Reviewer: ________ Date: ________"]
        return lines
    }

    /// Tags in `FoodTag.allCases` order, or "none".
    static func tagList(_ tags: Set<FoodTag>) -> String {
        let ordered = FoodTag.allCases.filter { tags.contains($0) }.map(\.rawValue)
        return ordered.isEmpty ? "none" : ordered.joined(separator: ", ")
    }

    static func amount(_ line: RecipeIngredientLine) -> String {
        let base: String
        switch line.unit {
        case .pinch: base = "a pinch"
        case .toTaste: base = "to taste"
        default: base = "\(number(line.quantity)) \(line.unit.rawValue)"
        }
        return line.isOptional ? base + " (optional)" : base
    }

    /// A locale-independent number: whole numbers without a decimal point, others as Swift's
    /// shortest round-trip representation ("0.5").
    static func number(_ value: Double) -> String {
        if value.isFinite, value == value.rounded(), abs(value) < 1e15 {
            return String(Int(value))
        }
        return String(value)
    }

    /// Escapes the markdown table separator.
    private static func cell(_ text: String) -> String {
        text.replacingOccurrences(of: "|", with: "\\|")
    }
}
