/// Where a shopping item came from (AC-10.5, AC-11.3).
public enum ShoppingItemOrigin: String, CaseIterable, Codable, Sendable, Hashable {
    /// Derived from the effectively approved plan; recomputed on re-derivation.
    case plan
    case manual
    case notesImport
}

/// Which list group an item is in (AC-10.4).
public enum ShoppingItemGroup: String, CaseIterable, Codable, Sendable, Hashable {
    case toBuy
    /// The pantry probably covers it, but confidence is low.
    case checkYouHave
}

/// A shopping-list line (plan section 3.1).
public struct ShoppingItem: Identifiable, Codable, Sendable, Hashable {
    public let id: ShoppingItemID
    /// Merge key for re-derivation (format owned by T14), so check-offs survive (AC-10.5).
    public var key: String
    public var ingredientId: IngredientID?
    /// Display name: the ingredient name, or the text the user typed or imported.
    public var name: String
    public var quantity: Double?
    public var unit: MeasureUnit?
    public var aisle: Aisle
    public var checkedOff: Bool
    public var origin: ShoppingItemOrigin
    public var group: ShoppingItemGroup

    public init(
        id: ShoppingItemID,
        key: String,
        ingredientId: IngredientID? = nil,
        name: String,
        quantity: Double? = nil,
        unit: MeasureUnit? = nil,
        aisle: Aisle,
        checkedOff: Bool = false,
        origin: ShoppingItemOrigin,
        group: ShoppingItemGroup = .toBuy
    ) {
        self.id = id
        self.key = key
        self.ingredientId = ingredientId
        self.name = name
        self.quantity = quantity
        self.unit = unit
        self.aisle = aisle
        self.checkedOff = checkedOff
        self.origin = origin
        self.group = group
    }
}
