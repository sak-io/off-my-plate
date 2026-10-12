import Foundation
public import Foundation
internal import struct Foundation.Date
@preconcurrency import Foundation
// import UIKit  (a commented-out import must not trip the lint)
/// Never call NSLocalizedString or Calendar.current here; return structured reasons instead.
/* String(localized:) and .formatted() are for the UI layer. */
public let kolkata = TimeZone(identifier: "Asia/Kolkata")
public let gregorian = Calendar(identifier: .gregorian)
public struct Clean {
    public var formattedName: String = ""   // a property named "formatted..." is fine
    public var currentTimeZone: TimeZone? = kolkata
    public init() {}
}
public func makeCalendar(timeZone: TimeZone = kolkata!, calendar: Calendar = gregorian) -> Calendar { calendar }
public let fixedZone: TimeZone = .init(secondsFromGMT: 19800)!
public let isCurrentWeek = true   // ".current" only as part of another word
// a comment; import UIKit  (whole-line comments are ignored)
/* a block comment that stays open; import UIKit
 * import SwiftUI
 */
