import Foundation
import OMPDomain

/// The outcome of validating one set of seed files.
public struct SeedValidationResult: Sendable, Hashable {
    /// Every defect found, in file order (catalog, ingredients, recipes). Empty when valid.
    public let issues: [SeedIssue]
    /// The library, present only when `issues` is empty.
    public let library: SeedLibrary?

    public var isValid: Bool {
        issues.isEmpty
    }
}

/// Checks seed content against schema v1 and the safety invariants of ADR 0010 / A3:
/// every id is unique and present, every enumerated value is known, every ingredient has an
/// aisle, tags and a tag status, every recipe line resolves to an ingredient with a convertible
/// unit, and every recipe's `declaredTags` equals the tags derived from its ingredients.
///
/// It reports all issues it can find rather than stopping at the first. A library is built only
/// from content with no issues at all: partial libraries are never returned.
/// Content-coverage targets (the 8/14/8 recipe split, sign-off before release) belong to the
/// content tasks and the release check, not to this structural validator.
public enum SeedValidator {
    /// The schema version this build reads.
    public static let supportedSchemaVersion = 1

    /// Validates `files` and, when they are clean, builds the library.
    public static func validate(_ files: SeedFiles) -> SeedValidationResult {
        var issues: [SeedIssue] = []
        let catalogDocument = decode(CatalogDocument.self, .catalog, files, &issues)
        let ingredientsDocument = decode(IngredientsDocument.self, .ingredients, files, &issues)
        let recipesDocument = decode(RecipesDocument.self, .recipes, files, &issues)
        guard let catalogDocument, let ingredientsDocument, let recipesDocument else {
            return SeedValidationResult(issues: issues, library: nil)
        }

        let contentVersion = checkHeader(
            .catalog, catalogDocument.schemaVersion, catalogDocument.contentVersion, expected: nil, &issues)
        _ = checkHeader(
            .ingredients, ingredientsDocument.schemaVersion, ingredientsDocument.contentVersion,
            expected: contentVersion, &issues)
        _ = checkHeader(
            .recipes, recipesDocument.schemaVersion, recipesDocument.contentVersion, expected: contentVersion,
            &issues)

        let catalog = validateCatalog(catalogDocument, &issues)
        let ingredientPass = validateIngredients(ingredientsDocument, &issues)
        let recipes = validateRecipes(
            recipesDocument, cuisines: Set(catalog.cuisines.map(\.id.rawValue)), ingredients: ingredientPass.facts,
            &issues)

        guard issues.isEmpty, let contentVersion else {
            return SeedValidationResult(issues: issues, library: nil)
        }
        let library = SeedLibrary(
            contentVersion: contentVersion, catalog: catalog, ingredients: ingredientPass.ingredients,
            recipes: recipes)
        return SeedValidationResult(issues: [], library: library)
    }

    // MARK: - Files

    private static func decode<Document: Decodable>(
        _ type: Document.Type, _ file: SeedFile, _ files: SeedFiles, _ issues: inout [SeedIssue]
    ) -> Document? {
        do {
            return try JSONDecoder().decode(type, from: files[file])
        } catch {
            issues.append(.malformedFile(file, detail: String(describing: error)))
            return nil
        }
    }

    /// Checks `schemaVersion` and `contentVersion`; returns the content version when present.
    private static func checkHeader(
        _ file: SeedFile, _ schemaVersion: Int?, _ contentVersion: String?, expected: String?,
        _ issues: inout [SeedIssue]
    ) -> String? {
        if let schemaVersion {
            if schemaVersion != supportedSchemaVersion {
                issues.append(.unsupportedSchemaVersion(file, found: schemaVersion))
            }
        } else {
            issues.append(.missingField(.file, id: file.rawValue, field: "schemaVersion"))
        }
        guard let version = nonEmpty(contentVersion) else {
            issues.append(.missingField(.file, id: file.rawValue, field: "contentVersion"))
            return nil
        }
        if let expected, version != expected {
            issues.append(.contentVersionMismatch(file, found: version, expected: expected))
        }
        return version
    }

    // MARK: - Catalog

    private static func validateCatalog(_ document: CatalogDocument, _ issues: inout [SeedIssue]) -> SeedCatalog {
        let tagLabels: [(FoodTag, String)] = closedSetLabels(
            document.foodTags, kind: .foodTag, field: "foodTags", &issues)
        let aisleLabels: [(Aisle, String)] = closedSetLabels(
            document.aisles, kind: .aisle, field: "aisles", &issues)
        let listedAisles = aisleLabels.map { $0.0 }
        if listedAisles.count == Aisle.allCases.count, listedAisles != Array(Aisle.allCases) {
            issues.append(
                .invalidValue(
                    .file, id: SeedFile.catalog.rawValue, field: "aisles",
                    detail: "must be in display order: " + Aisle.allCases.map(\.rawValue).joined(separator: ", ")))
        }

        var cuisines: [CatalogCuisine] = []
        if let entries = document.cuisines {
            var seen = Set<String>()
            for (index, entry) in entries.enumerated() {
                guard let id = nonEmpty(entry.id) else {
                    issues.append(.missingField(.cuisine, id: position(index), field: "id"))
                    continue
                }
                guard seen.insert(id).inserted else {
                    issues.append(.duplicateID(.cuisine, id: id))
                    continue
                }
                guard let labelKey = nonEmpty(entry.labelKey) else {
                    issues.append(.missingField(.cuisine, id: id, field: "labelKey"))
                    continue
                }
                cuisines.append(CatalogCuisine(id: CuisineID(id), labelKey: labelKey))
            }
        } else {
            issues.append(.missingField(.file, id: SeedFile.catalog.rawValue, field: "cuisines"))
        }

        var restrictions: [Restriction] = []
        var restrictionIDs = Set<String>()
        if let entries = document.restrictions {
            for (index, entry) in entries.enumerated() {
                guard let id = nonEmpty(entry.id) else {
                    issues.append(.missingField(.restriction, id: position(index), field: "id"))
                    continue
                }
                guard restrictionIDs.insert(id).inserted else {
                    issues.append(.duplicateID(.restriction, id: id))
                    continue
                }
                let before = issues.count
                let labelKey = nonEmpty(entry.labelKey)
                if labelKey == nil {
                    issues.append(.missingField(.restriction, id: id, field: "labelKey"))
                }
                let excluded = parseFoodTags(entry.excludedTags ?? [], .restriction, id, "excludedTags", &issues)
                if excluded.isEmpty, issues.count == before {
                    issues.append(.missingField(.restriction, id: id, field: "excludedTags"))
                }
                if issues.count == before, let labelKey {
                    restrictions.append(Restriction(id: RestrictionID(id), labelKey: labelKey, excludedTags: excluded))
                }
            }
        } else {
            issues.append(.missingField(.file, id: SeedFile.catalog.rawValue, field: "restrictions"))
        }

        var keywords: [String: [RestrictionID]] = [:]
        let keywordMap = document.restrictionKeywords ?? [:]
        for keyword in keywordMap.keys.sorted() {
            let targets = keywordMap[keyword] ?? []
            let normalised = keyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if normalised.isEmpty || normalised != keyword {
                issues.append(
                    .invalidValue(.keyword, id: keyword, field: "keyword", detail: "must be non-empty, lowercase and trimmed"))
                continue
            }
            if targets.isEmpty {
                issues.append(.missingField(.keyword, id: keyword, field: "restrictions"))
                continue
            }
            var resolved: [RestrictionID] = []
            for target in targets {
                if restrictionIDs.contains(target) {
                    resolved.append(RestrictionID(target))
                } else {
                    issues.append(.danglingRestriction(keyword: keyword, restriction: target))
                }
            }
            keywords[keyword] = resolved
        }

        var foodTagLabelKeys: [FoodTag: String] = [:]
        for (tag, labelKey) in tagLabels {
            foodTagLabelKeys[tag] = labelKey
        }
        var aisleLabelKeys: [Aisle: String] = [:]
        for (aisle, labelKey) in aisleLabels {
            aisleLabelKeys[aisle] = labelKey
        }
        return SeedCatalog(
            foodTagLabelKeys: foodTagLabelKeys, aisleLabelKeys: aisleLabelKeys, cuisines: cuisines,
            restrictions: restrictions, restrictionKeywords: keywords)
    }

    /// Validates the `{id, labelKey}` entries of a closed set (food tags, aisles) and reports
    /// cases the catalog does not list. Returns the valid entries in file order.
    private static func closedSetLabels<Value>(
        _ entries: [LabelledEntryDocument]?, kind: SeedEntityKind, field: String, _ issues: inout [SeedIssue]
    ) -> [(Value, String)] where Value: RawRepresentable & CaseIterable & Hashable, Value.RawValue == String {
        guard let entries else {
            issues.append(.missingField(.file, id: SeedFile.catalog.rawValue, field: field))
            return []
        }
        var result: [(Value, String)] = []
        var seen = Set<String>()
        var listed = Set<Value>()
        for (index, entry) in entries.enumerated() {
            guard let raw = nonEmpty(entry.id) else {
                issues.append(.missingField(kind, id: position(index), field: "id"))
                continue
            }
            guard seen.insert(raw).inserted else {
                issues.append(.duplicateID(kind, id: raw))
                continue
            }
            guard let value = Value(rawValue: raw) else {
                issues.append(.unknownValue(kind, id: raw, field: "id", value: raw))
                continue
            }
            listed.insert(value)
            guard let labelKey = nonEmpty(entry.labelKey) else {
                issues.append(.missingField(kind, id: raw, field: "labelKey"))
                continue
            }
            result.append((value, labelKey))
        }
        let missing = Value.allCases.filter { !listed.contains($0) }.map(\.rawValue)
        if !missing.isEmpty {
            issues.append(.catalogIncomplete(field: field, missing: missing))
        }
        return result
    }

    // MARK: - Ingredients

    /// What recipe validation needs to know about an ingredient that has a usable id, even if
    /// another of its fields is broken (so recipes are not also reported as dangling).
    struct IngredientFacts {
        var tags: Set<FoodTag>
        var defaultUnit: MeasureUnit?
        var gramsPerMl: Double?
        var gramsPerPiece: Double?
    }

    private static func validateIngredients(
        _ document: IngredientsDocument, _ issues: inout [SeedIssue]
    ) -> (ingredients: [Ingredient], facts: [String: IngredientFacts]) {
        guard let entries = document.ingredients else {
            issues.append(.missingField(.file, id: SeedFile.ingredients.rawValue, field: "ingredients"))
            return ([], [:])
        }
        var ingredients: [Ingredient] = []
        var facts: [String: IngredientFacts] = [:]
        var namesToIDs: [String: Set<String>] = [:]

        for (index, entry) in entries.enumerated() {
            guard let id = nonEmpty(entry.id) else {
                issues.append(.missingField(.ingredient, id: position(index), field: "id"))
                continue
            }
            guard facts[id] == nil else {
                issues.append(.duplicateID(.ingredient, id: id))
                continue
            }
            let before = issues.count

            let name = nonEmpty(entry.name)
            if name == nil {
                issues.append(.missingField(.ingredient, id: id, field: "name"))
            }
            let synonyms = entry.synonyms ?? []
            if synonyms.contains(where: { nonEmpty($0) == nil }) {
                issues.append(.invalidValue(.ingredient, id: id, field: "synonyms", detail: "a synonym is empty"))
            }
            for text in [name ?? ""] + synonyms {
                let key = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if !key.isEmpty {
                    namesToIDs[key, default: []].insert(id)
                }
            }

            var tags = Set<FoodTag>()
            if let rawTags = entry.tags {
                tags = parseFoodTags(rawTags, .ingredient, id, "tags", &issues)
            } else {
                issues.append(.missingField(.ingredient, id: id, field: "tags"))
            }
            let mayContain = parseFoodTags(entry.mayContain ?? [], .ingredient, id, "mayContain", &issues)
            let tagStatus: TagStatus? = closedValue(entry.tagStatus, .ingredient, id, "tagStatus", &issues)
            let aisle: Aisle? = closedValue(entry.aisle, .ingredient, id, "aisle", &issues)
            let defaultUnit: MeasureUnit? = closedValue(entry.defaultUnit, .ingredient, id, "defaultUnit", &issues)
            let location: StorageLocation? = closedValue(
                entry.defaultLocation, .ingredient, id, "defaultLocation", &issues)
            checkPositive(entry.gramsPerMl, .ingredient, id, "gramsPerMl", &issues)
            checkPositive(entry.gramsPerPiece, .ingredient, id, "gramsPerPiece", &issues)
            if let days = entry.fridgeShelfLifeDays, days <= 0 {
                issues.append(.invalidValue(.ingredient, id: id, field: "fridgeShelfLifeDays", detail: "must be positive"))
            }

            facts[id] = IngredientFacts(
                tags: tags.union(mayContain), defaultUnit: defaultUnit, gramsPerMl: entry.gramsPerMl,
                gramsPerPiece: entry.gramsPerPiece)

            guard issues.count == before, let name, let tagStatus, let aisle, let defaultUnit, let location else {
                continue
            }
            ingredients.append(
                Ingredient(
                    id: IngredientID(id), name: name, synonyms: synonyms, tags: tags, mayContain: mayContain,
                    tagStatus: tagStatus, aisle: aisle, defaultUnit: defaultUnit, gramsPerMl: entry.gramsPerMl,
                    gramsPerPiece: entry.gramsPerPiece, defaultLocation: location,
                    fridgeShelfLifeDays: entry.fridgeShelfLifeDays))
        }

        for key in namesToIDs.keys.sorted() {
            if let ids = namesToIDs[key], ids.count > 1 {
                issues.append(.ambiguousName(key, ingredients: ids.sorted()))
            }
        }
        return (ingredients, facts)
    }

    // MARK: - Recipes

    private static func validateRecipes(
        _ document: RecipesDocument, cuisines: Set<String>, ingredients: [String: IngredientFacts],
        _ issues: inout [SeedIssue]
    ) -> [Recipe] {
        guard let entries = document.recipes else {
            issues.append(.missingField(.file, id: SeedFile.recipes.rawValue, field: "recipes"))
            return []
        }
        var recipes: [Recipe] = []
        var seen = Set<String>()

        for (index, entry) in entries.enumerated() {
            guard let id = nonEmpty(entry.id) else {
                issues.append(.missingField(.recipe, id: position(index), field: "id"))
                continue
            }
            guard seen.insert(id).inserted else {
                issues.append(.duplicateID(.recipe, id: id))
                continue
            }
            let before = issues.count

            let title = nonEmpty(entry.title)
            if title == nil {
                issues.append(.missingField(.recipe, id: id, field: "title"))
            }
            let region = nonEmpty(entry.region)
            if let region {
                if !cuisines.contains(region) {
                    issues.append(.unknownValue(.recipe, id: id, field: "region", value: region))
                }
            } else {
                issues.append(.missingField(.recipe, id: id, field: "region"))
            }

            var mealTypes = Set<MealType>()
            for raw in entry.mealTypes ?? [] {
                if let mealType = MealType(rawValue: raw) {
                    mealTypes.insert(mealType)
                } else {
                    issues.append(.unknownValue(.recipe, id: id, field: "mealTypes", value: raw))
                }
            }
            if (entry.mealTypes ?? []).isEmpty {
                issues.append(.missingField(.recipe, id: id, field: "mealTypes"))
            }

            if let servings = entry.servings {
                if servings <= 0 {
                    issues.append(.invalidValue(.recipe, id: id, field: "servings", detail: "must be positive"))
                }
            } else {
                issues.append(.missingField(.recipe, id: id, field: "servings"))
            }
            for (field, minutes) in [("prepMinutes", entry.prepMinutes), ("cookMinutes", entry.cookMinutes)] {
                if let minutes {
                    if minutes < 0 {
                        issues.append(.invalidValue(.recipe, id: id, field: field, detail: "must not be negative"))
                    }
                } else {
                    issues.append(.missingField(.recipe, id: id, field: field))
                }
            }

            let lineResult = validateLines(entry.ingredients, recipe: id, ingredients: ingredients, &issues)

            let steps = entry.steps ?? []
            if steps.isEmpty {
                issues.append(.missingField(.recipe, id: id, field: "steps"))
            } else if steps.contains(where: { nonEmpty($0) == nil }) {
                issues.append(.invalidValue(.recipe, id: id, field: "steps", detail: "a step is empty"))
            }

            var declared = Set<FoodTag>()
            if let rawDeclared = entry.declaredTags {
                let beforeTags = issues.count
                declared = parseFoodTags(rawDeclared, .recipe, id, "declaredTags", &issues)
                if issues.count == beforeTags, lineResult.allResolved {
                    let derived = lineResult.derivedTags
                    let undeclared = FoodTag.allCases.filter { derived.contains($0) && !declared.contains($0) }
                    let unsupported = FoodTag.allCases.filter { declared.contains($0) && !derived.contains($0) }
                    if !undeclared.isEmpty || !unsupported.isEmpty {
                        issues.append(
                            .declaredTagsMismatch(recipe: id, undeclared: undeclared, unsupported: unsupported))
                    }
                }
            } else {
                issues.append(.missingField(.recipe, id: id, field: "declaredTags"))
            }

            let source = nonEmpty(entry.provenance?.source)
            if source == nil {
                issues.append(.missingField(.recipe, id: id, field: "provenance.source"))
            }
            let review = validateReview(entry.review, recipe: id, &issues)

            guard issues.count == before, let title, let region, let servings = entry.servings,
                let prepMinutes = entry.prepMinutes, let cookMinutes = entry.cookMinutes, let source, let review
            else { continue }
            recipes.append(
                Recipe(
                    id: RecipeID(id), title: title, region: CuisineID(region), mealTypes: mealTypes,
                    lunchboxSuitable: entry.lunchboxSuitable ?? false, servings: servings, prepMinutes: prepMinutes,
                    cookMinutes: cookMinutes, ingredients: lineResult.lines, steps: steps, declaredTags: declared,
                    provenance: RecipeProvenance(source: source, notes: nonEmpty(entry.provenance?.notes)),
                    review: review))
        }
        return recipes
    }

    private static func validateLines(
        _ entries: [RecipeLineDocument]?, recipe id: String, ingredients: [String: IngredientFacts],
        _ issues: inout [SeedIssue]
    ) -> (lines: [RecipeIngredientLine], derivedTags: Set<FoodTag>, allResolved: Bool) {
        guard let entries, !entries.isEmpty else {
            issues.append(.missingField(.recipe, id: id, field: "ingredients"))
            return ([], [], false)
        }
        var lines: [RecipeIngredientLine] = []
        var derived = Set<FoodTag>()
        var allResolved = true
        for (index, entry) in entries.enumerated() {
            let path = "ingredients[\(index)]"
            guard let ingredientID = nonEmpty(entry.ingredientId) else {
                issues.append(.missingField(.recipe, id: id, field: "\(path).ingredientId"))
                allResolved = false
                continue
            }
            let facts = ingredients[ingredientID]
            if let facts {
                derived.formUnion(facts.tags)
            } else {
                issues.append(.danglingIngredient(recipe: id, ingredient: ingredientID))
                allResolved = false
            }
            let parsedUnit: MeasureUnit? = closedValue(entry.unit, .recipe, id, "\(path).unit", &issues)
            guard let unit = parsedUnit else { continue }
            let quantity = entry.quantity ?? 0
            if unit.dimension == .unquantified {
                if quantity < 0 || !quantity.isFinite {
                    issues.append(.invalidValue(.recipe, id: id, field: "\(path).quantity", detail: "must not be negative"))
                }
            } else if !(quantity > 0) || !quantity.isFinite {
                issues.append(
                    .invalidValue(
                        .recipe, id: id, field: "\(path).quantity",
                        detail: "must be a positive number for unit '\(unit.rawValue)'"))
            }
            if let facts, let defaultUnit = facts.defaultUnit, !isConvertible(unit, to: defaultUnit, facts) {
                issues.append(.unconvertibleUnit(recipe: id, ingredient: ingredientID, unit: unit))
            }
            lines.append(
                RecipeIngredientLine(
                    ingredientId: IngredientID(ingredientID), quantity: quantity, unit: unit,
                    isOptional: entry.optional ?? false))
        }
        return (lines, derived, allResolved)
    }

    private static func validateReview(
        _ document: ReviewDocument?, recipe id: String, _ issues: inout [SeedIssue]
    ) -> RecipeReview? {
        guard let document else {
            issues.append(.missingField(.recipe, id: id, field: "review"))
            return nil
        }
        let status: RecipeReviewStatus? = closedValue(document.status, .recipe, id, "review.status", &issues)
        var reviewedOn: LocalDate?
        if let raw = document.reviewedOn {
            reviewedOn = LocalDate(isoString: raw)
            if reviewedOn == nil {
                issues.append(.invalidValue(.recipe, id: id, field: "review.reviewedOn", detail: "'\(raw)' is not YYYY-MM-DD"))
            }
        }
        let reviewer = nonEmpty(document.reviewer)
        if status == .signedOff, reviewer == nil || reviewedOn == nil {
            issues.append(
                .invalidValue(.recipe, id: id, field: "review", detail: "signedOff needs a reviewer and reviewedOn"))
        }
        guard let status else { return nil }
        return RecipeReview(status: status, reviewer: reviewer, reviewedOn: reviewedOn)
    }

    /// Whether a recipe line in `unit` is usable for an ingredient whose default unit is
    /// `defaultUnit`:
    /// - a non-quantified line (pinch, to taste) is always fine: it never reaches the list;
    /// - a quantified line needs a quantified default unit (lead decision, T04 review 1: an
    ///   unquantified default unit is allowed only if every line using it is unquantified);
    /// - otherwise T07's `ConversionProfile.canConvert` decides, with the ingredient's
    ///   density and piece weight.
    static func isConvertible(_ unit: MeasureUnit, to defaultUnit: MeasureUnit, _ facts: IngredientFacts) -> Bool {
        if unit.dimension == .unquantified {
            return true
        }
        if defaultUnit.dimension == .unquantified {
            return false
        }
        let profile = ConversionProfile(gramsPerMl: facts.gramsPerMl, gramsPerPiece: facts.gramsPerPiece)
        return profile.canConvert(from: unit, to: defaultUnit)
    }

    // MARK: - Helpers

    /// The trimmed string, or nil when it is absent or blank.
    private static func nonEmpty(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// A 1-based placeholder id for an entry without one.
    private static func position(_ index: Int) -> String {
        "#\(index + 1)"
    }

    private static func parseFoodTags(
        _ raws: [String], _ kind: SeedEntityKind, _ id: String, _ field: String, _ issues: inout [SeedIssue]
    ) -> Set<FoodTag> {
        var tags = Set<FoodTag>()
        for raw in raws {
            if let tag = FoodTag(rawValue: raw) {
                tags.insert(tag)
            } else {
                issues.append(.unknownValue(kind, id: id, field: field, value: raw))
            }
        }
        return tags
    }

    /// Parses a required value of a closed set, reporting it as missing or unknown.
    private static func closedValue<Value: RawRepresentable>(
        _ raw: String?, _ kind: SeedEntityKind, _ id: String, _ field: String, _ issues: inout [SeedIssue]
    ) -> Value? where Value.RawValue == String {
        guard let raw = nonEmpty(raw) else {
            issues.append(.missingField(kind, id: id, field: field))
            return nil
        }
        guard let value = Value(rawValue: raw) else {
            issues.append(.unknownValue(kind, id: id, field: field, value: raw))
            return nil
        }
        return value
    }

    private static func checkPositive(
        _ value: Double?, _ kind: SeedEntityKind, _ id: String, _ field: String, _ issues: inout [SeedIssue]
    ) {
        if let value, !(value > 0) || !value.isFinite {
            issues.append(.invalidValue(kind, id: id, field: field, detail: "must be positive"))
        }
    }
}
