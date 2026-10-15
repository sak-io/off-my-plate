import OMPDomain
import OMPServices

/// Placeholder for the SwiftData persistence layer (ADR 0003, task T20).
///
/// Exists so the Apple package resolves `../Core` by path and links the Core modules the
/// data layer will need, from the first app build on.
public enum OMPDataModule {
    /// The Core version this module was built against.
    public static let coreVersion: String = OMPVersion.current
}
