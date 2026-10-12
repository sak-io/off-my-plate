import OMPDomain

/// Placeholder for the Apple capture adapters: on-device speech capture only in v1
/// (ADR 0004, ADR 0012, task T30). The text and voice-grammar parsers live in `OMPDomain`.
public enum OMPCaptureModule {
    /// The Core version this module was built against.
    public static let coreVersion: String = OMPVersion.current
}
