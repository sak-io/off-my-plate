/// A restriction offered on the safety screen, for example "Peanuts" or "Jain" (catalog entry).
///
/// Restrictions come from the seed `catalog.json` (task T04). Their tag sets are a product
/// safety decision signed off by the owner (plan R4: "vegetarian" excludes egg, "Jain"
/// excludes root vegetables, onion, garlic and mushroom).
public struct Restriction: Identifiable, Codable, Sendable, Hashable {
    public let id: RestrictionID
    /// String Catalog key for the chip label; the UI localises it (ADR 0005).
    public var labelKey: String
    /// The tags a rule for this restriction excludes.
    public var excludedTags: Set<FoodTag>

    public init(id: RestrictionID, labelKey: String, excludedTags: Set<FoodTag>) {
        self.id = id
        self.labelKey = labelKey
        self.excludedTags = excludedTags
    }
}
