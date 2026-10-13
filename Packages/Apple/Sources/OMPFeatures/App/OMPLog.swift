import Foundation
import os

/// Loggers for the app (os `Logger`). Rules (privacy-compliance, ADR 0015):
/// - Never log household content: names, safety answers, rules, pantry or plan contents.
/// - Interpolate only counts, enum case names and error type names, and mark them
///   `privacy: .public` explicitly; anything else stays at the default `.private` redaction.
public enum OMPLog {
    /// The subsystem: the app's bundle identifier.
    public static var subsystem: String {
        Bundle.main.bundleIdentifier ?? "OffMyPlate"
    }

    /// App launch, composition root and the store.
    public static var app: Logger { Logger(subsystem: subsystem, category: "app") }

    /// The safety gate status as the shell sees it.
    public static var gate: Logger { Logger(subsystem: subsystem, category: "gate") }

    /// A data-free description of `error` for logs: its type name only, never its message,
    /// which could contain user data.
    public static func errorKind(_ error: any Error) -> String {
        String(describing: type(of: error))
    }
}
