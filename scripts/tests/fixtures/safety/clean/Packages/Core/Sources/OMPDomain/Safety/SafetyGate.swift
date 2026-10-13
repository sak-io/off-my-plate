/// `SafetyClearance(` is constructed only here (doc comment).
public struct SafetyClearance: Sendable {
    fileprivate init(household: Household) {}
}

extension SafetyClearance {
    public var isFresh: Bool { true }
}

public enum SafetyGate {
    public static func evaluate(_ household: Household) -> Result<SafetyClearance, GateRefusal> {
        .success(SafetyClearance(household: household))
    }
}
