import Foundation

/// The scheduling state of one contextual prompt (plan sections 3.1 and 7). The scheduler
/// itself is task T17.
public struct PromptState: Identifiable, Codable, Sendable, Hashable {
    public var promptId: PromptID
    public var lastShownAt: Date?
    /// Starts the 14-day cooldown (AC-7.3).
    public var dismissedAt: Date?
    public var answeredAt: Date?

    public init(promptId: PromptID, lastShownAt: Date? = nil, dismissedAt: Date? = nil, answeredAt: Date? = nil) {
        self.promptId = promptId
        self.lastShownAt = lastShownAt
        self.dismissedAt = dismissedAt
        self.answeredAt = answeredAt
    }

    public var id: PromptID {
        promptId
    }
}
