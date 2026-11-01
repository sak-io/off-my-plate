import Testing
import OMPData
import OMPDomain

@Suite("OMPData placeholder")
struct OMPDataModuleTests {
    @Test("OMPData links the Core package and was built against the current Core version")
    func linksCurrentCore() {
        #expect(OMPDataModule.coreVersion == OMPVersion.current)
        #expect(!OMPDataModule.coreVersion.isEmpty)
    }
}
