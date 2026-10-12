import Foundation
import struct Foundation.Date
@preconcurrency import Foundation
// import UIKit  (a commented-out import must not trip the lint)
/// Never call NSLocalizedString here; return structured reasons instead.
/* String(localized:) is for the UI layer. */
public let isoFormatterIsFine = ISO8601DateFormatter.self
public struct Clean { public init() {} }
