import Testing
import OMPDomain

@Suite("OMPVersion")
struct OMPVersionTests {
    @Test("current is a MAJOR.MINOR.PATCH version made of ASCII digits")
    func currentIsSemanticVersion() {
        let parts = OMPVersion.current.split(separator: ".", omitEmptySubsequences: false)
        #expect(parts.count == 3)
        for part in parts {
            #expect(!part.isEmpty)
            #expect(part.utf8.allSatisfy { $0 >= UInt8(ascii: "0") && $0 <= UInt8(ascii: "9") })
        }
    }

    @Test("current is the first development version, 0.1.0")
    func currentIsInitialVersion() {
        #expect(OMPVersion.current == "0.1.0")
    }
}
