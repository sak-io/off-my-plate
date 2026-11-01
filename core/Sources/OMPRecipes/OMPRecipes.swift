import OMPDomain

/// Seed content (ADR 0010): `SeedLoader` reads the bundled JSON, `SeedValidator` checks it and
/// builds the read-only `SeedLibrary`, and `SeedReviewSheet` renders the sign-off sheet.
public enum OMPRecipesModule {
    /// The core version this module was built with.
    public static let coreVersion: String = OMPVersion.current
}
