import Foundation

/// The single source of "now" for the core (ADR 0005: determinism through an injected clock).
///
/// Named `DomainClock` rather than `Clock` so it cannot clash with the standard library's
/// `Clock` protocol (Swift 5.7+) in modules that import `OMPDomain`.
///
/// A clock always carries an explicit time zone: the core never reads the device's current
/// time zone itself. The app's composition root builds a `SystemClock` with the device time
/// zone; tests use `FixedClock`.
public protocol DomainClock: Sendable {
    /// The current instant.
    var now: Date { get }
    /// The time zone used to turn instants into calendar days.
    var timeZone: TimeZone { get }
}

extension DomainClock {
    /// The calendar day containing `now` in this clock's time zone.
    public var today: LocalDate {
        LocalDate(now, in: timeZone)
    }
}

/// The real clock. The time zone must be passed in by the caller (the app).
public struct SystemClock: DomainClock {
    public let timeZone: TimeZone

    public init(timeZone: TimeZone) {
        self.timeZone = timeZone
    }

    public var now: Date {
        Date()
    }
}

/// A clock that always returns the same instant, for tests and previews.
public struct FixedClock: DomainClock {
    public var now: Date
    public var timeZone: TimeZone

    public init(now: Date, timeZone: TimeZone) {
        self.now = now
        self.timeZone = timeZone
    }
}
