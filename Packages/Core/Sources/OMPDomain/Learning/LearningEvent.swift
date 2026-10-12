import Foundation

/// A re-roll reason chip (AC-8.2).
public enum RerollReason: String, CaseIterable, Codable, Sendable, Hashable {
    case dontFeelLikeIt
    case tooLong
    case kidsWontEatIt
}

/// An answer on a reflect-back card (AC-12.2, AC-12.3).
public enum ReflectBackAnswer: String, CaseIterable, Codable, Sendable, Hashable {
    case yes
    case notReally
    case dontAskAgain
}

/// What happened, with its payload (AC-12.1). Signals only; none of them carry safety data
/// (AC-11.5, AC-12.4).
public enum LearningEventKind: Codable, Sendable, Hashable {
    case swapped(from: RecipeID, to: RecipeID, slot: MealSlot)
    case rerolled(recipe: RecipeID, slot: MealSlot, reason: RerollReason?)
    case skipped(recipe: RecipeID, slot: MealSlot)
    case cooked(recipe: RecipeID)
    /// A resolved item from a Notes import: staple evidence only (AC-11.5).
    case importedItem(ingredient: IngredientID)
    case reflectBackAnswered(key: FactKey, answer: ReflectBackAnswer)
}

/// One on-device learning signal (plan section 3.1, ADR 0013). Pruned after 12 months.
public struct LearningEvent: Identifiable, Codable, Sendable, Hashable {
    public let id: LearningEventID
    public var kind: LearningEventKind
    public var at: Date

    public init(id: LearningEventID, kind: LearningEventKind, at: Date) {
        self.id = id
        self.kind = kind
        self.at = at
    }
}
