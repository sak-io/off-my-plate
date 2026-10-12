import OMPDomain

/// Placeholder for the seed-content loader and validator (ADR 0010, task T04).
///
/// Exists so the target builds and its dependency on `OMPDomain` is exercised from day one.
public enum OMPRecipesModule {
    /// The core version this module was built with.
    public static let coreVersion: String = OMPVersion.current
}
