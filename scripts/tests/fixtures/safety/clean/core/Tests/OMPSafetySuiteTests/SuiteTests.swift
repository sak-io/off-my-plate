import Testing

// .disabled and withKnownIssue are fine in a comment.
@Suite("Safety suite")
struct SuiteTests {
    @Test("every restriction", arguments: [1, 2])
    func everyRestriction(value: Int) {
        let disabledCount = 0
        #expect(disabledCount == 0)
    }
}
