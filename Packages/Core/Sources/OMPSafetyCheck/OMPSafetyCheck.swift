import OMPDomain

/// Module marker for the independent plan validator (`PlanValidator`, ADR 0007).
public enum OMPSafetyCheckModule {
    /// The core version this module was built with.
    public static let coreVersion: String = OMPVersion.current
}
