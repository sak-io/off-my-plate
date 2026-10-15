/// An allergen or diet tag on an ingredient (plan section 3.1).
///
/// A recipe's tags are derived from its ingredients; hard rules exclude tags. The set is
/// closed in v1: adding a tag is a code change, reviewed together with the seed catalog.
/// Encodes as the case name.
public enum FoodTag: String, CaseIterable, Codable, Sendable, Hashable {
    case peanut
    case treeNut
    case milk
    case egg
    case wheat
    case gluten
    case soy
    case sesame
    case mustard
    case fish
    case shellfish
    case beef
    case pork
    case poultry
    case otherMeat
    case gelatin
    case rootVegetable
    case onion
    case garlic
    case mushroom
}

/// Whether an ingredient's tags have been checked (AC-4.3).
///
/// An `unverified` ingredient may be missing tags, so a recipe that uses it is excluded for
/// any eater with a hard rule.
public enum TagStatus: String, CaseIterable, Codable, Sendable, Hashable {
    case verified
    case unverified
}
