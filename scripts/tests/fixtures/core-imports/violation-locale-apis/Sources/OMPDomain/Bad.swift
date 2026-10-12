import Foundation
let a = MeasurementFormatter()
let b = ISO8601DateFormatter()
let c = Date.now.formatted(date: .abbreviated, time: .omitted)
let d = Calendar.current
let e = Locale.autoupdatingCurrent
let f = TimeZone.current
let g: TimeZone = .current
var h: Calendar? = .autoupdatingCurrent
let i = Date.FormatStyle(locale: .current)
func j(calendar: Calendar = Calendar(identifier: .gregorian), timeZone: TimeZone) -> Date.ComponentsFormatStyle? { nil }
let k = j(timeZone: .autoupdatingCurrent)
let l = NSTimeZone.local
let m = NSLocale.system
let n = NSCalendar.current
c.timeZone = .current
c.locale = .autoupdatingCurrent
let same = x.timeZone == .current
let differs = x.calendar != .current
let forced: TimeZone! = .current
/* a note */ let late = TimeZone.current
