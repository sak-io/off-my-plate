import OMPDomain

/// What kind of seed entry an issue is about.
public enum SeedEntityKind: String, Sendable, Hashable {
    /// A whole file (its header or a top-level section).
    case file
    case foodTag
    case aisle
    case cuisine
    case restriction
    case keyword
    case ingredient
    case recipe
}

/// One defect found by `SeedValidator`. Any issue rejects the whole seed library.
///
/// Ids are the raw strings from the JSON. An entry without an id is identified by its 1-based
/// position, for example `"#3"`. Descriptions are developer-facing English (test output and the
/// review-sheet tool), never shown in the app.
public enum SeedIssue: Hashable, Sendable, CustomStringConvertible {
    /// The file is not valid JSON or a field has the wrong JSON type.
    case malformedFile(SeedFile, detail: String)
    /// `schemaVersion` is not one this build understands.
    case unsupportedSchemaVersion(SeedFile, found: Int)
    /// The file's `contentVersion` differs from the catalog's.
    case contentVersionMismatch(SeedFile, found: String, expected: String)
    /// A required field is absent or empty.
    case missingField(SeedEntityKind, id: String, field: String)
    /// Two entries of the same kind share an id.
    case duplicateID(SeedEntityKind, id: String)
    /// A value that is not in its closed set: a food tag, aisle, unit, storage location, meal
    /// type, tag status, review status or cuisine.
    case unknownValue(SeedEntityKind, id: String, field: String, value: String)
    /// A value that is present and known but not allowed (a non-positive quantity, a
    /// signed-off recipe without a reviewer, aisles out of display order, ...).
    case invalidValue(SeedEntityKind, id: String, field: String, detail: String)
    /// The catalog does not list every case of a closed set (`foodTags` or `aisles`).
    case catalogIncomplete(field: String, missing: [String])
    /// A keyword in `restrictionKeywords` points at a restriction that does not exist.
    case danglingRestriction(keyword: String, restriction: String)
    /// Two ingredients share a name or synonym (case-insensitive), so text could resolve to
    /// either of them.
    case ambiguousName(String, ingredients: [String])
    /// A recipe line names an ingredient that does not exist.
    case danglingIngredient(recipe: String, ingredient: String)
    /// A recipe line uses a unit that cannot be converted to the ingredient's default unit,
    /// because the ingredient lacks the density or piece weight that would bridge them.
    case unconvertibleUnit(recipe: String, ingredient: String, unit: MeasureUnit)
    /// `declaredTags` differs from the tags derived from the ingredients. `undeclared` are
    /// derived but not declared (the dangerous direction); `unsupported` are declared but not
    /// derived. Both lists are in `FoodTag.allCases` order.
    case declaredTagsMismatch(recipe: String, undeclared: [FoodTag], unsupported: [FoodTag])

    public var description: String {
        switch self {
        case .malformedFile(let file, let detail):
            return "\(file.rawValue): not valid seed JSON (\(detail))"
        case .unsupportedSchemaVersion(let file, let found):
            return "\(file.rawValue): schemaVersion \(found) is not supported (expected \(SeedValidator.supportedSchemaVersion))"
        case .contentVersionMismatch(let file, let found, let expected):
            return "\(file.rawValue): contentVersion '\(found)' differs from the catalog's '\(expected)'"
        case .missingField(let kind, let id, let field):
            return "\(kind.rawValue) '\(id)': missing \(field)"
        case .duplicateID(let kind, let id):
            return "\(kind.rawValue) '\(id)': duplicate id"
        case .unknownValue(let kind, let id, let field, let value):
            return "\(kind.rawValue) '\(id)': unknown \(field) '\(value)'"
        case .invalidValue(let kind, let id, let field, let detail):
            return "\(kind.rawValue) '\(id)': invalid \(field): \(detail)"
        case .catalogIncomplete(let field, let missing):
            return "catalog.json: \(field) is missing \(missing.joined(separator: ", "))"
        case .danglingRestriction(let keyword, let restriction):
            return "keyword '\(keyword)': unknown restriction '\(restriction)'"
        case .ambiguousName(let name, let ingredients):
            return "name or synonym '\(name)' is used by several ingredients: \(ingredients.joined(separator: ", "))"
        case .danglingIngredient(let recipe, let ingredient):
            return "recipe '\(recipe)': unknown ingredient '\(ingredient)'"
        case .unconvertibleUnit(let recipe, let ingredient, let unit):
            return "recipe '\(recipe)': '\(unit.rawValue)' cannot be converted for ingredient '\(ingredient)' (add gramsPerMl or gramsPerPiece)"
        case .declaredTagsMismatch(let recipe, let undeclared, let unsupported):
            let missing = undeclared.map(\.rawValue).joined(separator: ", ")
            let extra = unsupported.map(\.rawValue).joined(separator: ", ")
            return "recipe '\(recipe)': declaredTags differ from the ingredients (undeclared: [\(missing)], unsupported: [\(extra)])"
        }
    }
}

/// Why the seed library could not be loaded.
public enum SeedLoadError: Error, Sendable, Hashable, CustomStringConvertible {
    /// A seed file is not in the bundle.
    case resourceMissing(SeedFile)
    /// The files were read but failed validation.
    case invalid([SeedIssue])

    public var description: String {
        switch self {
        case .resourceMissing(let file):
            return "seed resource \(file.rawValue) is missing from the bundle"
        case .invalid(let issues):
            return "seed content is invalid:\n" + issues.map { "  - \($0)" }.joined(separator: "\n")
        }
    }
}
