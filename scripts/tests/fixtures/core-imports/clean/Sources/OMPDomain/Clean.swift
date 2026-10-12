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
