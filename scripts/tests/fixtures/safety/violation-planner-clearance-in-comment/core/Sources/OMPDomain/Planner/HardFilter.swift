public enum HardFilter {
    public static func fits(_ entry: Entry, slot: MealSlot) -> Bool { true }

    public static func candidatesForAnyone(slot: MealSlot) -> [Entry] { // clearance: SafetyClearance
        []
    }

    nonisolated public static func unsafeCandidates(slot: MealSlot, note: String = "SafetyClearance") -> [Entry] {
        []
    }
}
