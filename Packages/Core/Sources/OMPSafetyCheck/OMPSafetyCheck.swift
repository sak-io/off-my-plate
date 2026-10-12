import OMPDomain

/// Placeholder for the independent plan validator (`PlanValidator`, ADR 0007, task T09).
///
/// Exists so the target builds and its dependency on `OMPDomain` is exercised from day one.
public enum OMPSafetyCheckModule {
    /// The core version this module was built with.
    public static let coreVersion: String = OMPVersion.current
}
