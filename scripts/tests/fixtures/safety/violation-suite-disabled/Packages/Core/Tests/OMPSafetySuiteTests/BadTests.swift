import Testing

@Suite("Safety suite")
struct BadTests {
    @Test(.disabled("flaky on CI"))
    func everyRestriction() {}

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func everyPair() {}

    @Test func generatedHouseholds() {
        withKnownIssue("planner bug") {
            #expect(Bool(false))
        }
    }

#if os(macOS)
    @Test func macOnly() {}
#endif
}
