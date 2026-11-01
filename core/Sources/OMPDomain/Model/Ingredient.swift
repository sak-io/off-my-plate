/// A shopping-list aisle (AC-10.3). `allCases` is the display order.
public enum Aisle: String, CaseIterable, Codable, Sendable, Hashable {
    case vegetablesAndFruit
    case dairyAndEggs
    case grainsAndFlours
    case pulsesAndLentils
    case spicesAndMasalas
    case oilsAndGhee
    case meatAndFish
    case bakery
    case other
}

/// Where a pantry item is kept (AC-9.1).
public enum StorageLocation: String, CaseIterable, Codable, Sendable, Hashable {
    case fridge
    case freezer
    case shelf
}

/// An entry in the ingredient taxonomy (plan section 3.1; seed content, ADR 0010).
public struct Ingredient: Identifiable, Codable, Sendable, Hashable {
    public let id: IngredientID
    public var name: String
    /// Other names and transliterations ("dahi", "curd", "yogurt").
    public var synonyms: [String]
    /// Allergen and diet tags the ingredient definitely has.
    public var tags: Set<FoodTag>
    /// Tags it may contain (cross-contact, compounded hing). Treated as "contains" by every
    /// safety check (ADR 0007).
    public var mayContain: Set<FoodTag>
    public var tagStatus: TagStatus
    public var aisle: Aisle
    public var defaultUnit: MeasureUnit
    /// Density for volume <-> mass conversion.
    public var gramsPerMl: Double?
    /// Weight of one piece for count <-> mass conversion.
    public var gramsPerPiece: Double?
    public var defaultLocation: StorageLocation
    public var fridgeShelfLifeDays: Int?

    public init(
        id: IngredientID,
        name: String,
        synonyms: [String] = [],
        tags: Set<FoodTag> = [],
        mayContain: Set<FoodTag> = [],
        tagStatus: TagStatus,
        aisle: Aisle,
        defaultUnit: MeasureUnit,
        gramsPerMl: Double? = nil,
        gramsPerPiece: Double? = nil,
        defaultLocation: StorageLocation,
        fridgeShelfLifeDays: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.synonyms = synonyms
        self.tags = tags
        self.mayContain = mayContain
        self.tagStatus = tagStatus
        self.aisle = aisle
        self.defaultUnit = defaultUnit
        self.gramsPerMl = gramsPerMl
        self.gramsPerPiece = gramsPerPiece
        self.defaultLocation = defaultLocation
        self.fridgeShelfLifeDays = fridgeShelfLifeDays
    }
}
