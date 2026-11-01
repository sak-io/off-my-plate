import Foundation

/// Cleans untrusted voice and safety text before it is split into words.
///
/// Swift groups a space followed by a combining mark (or joiner, variation selector, emoji
/// modifier) into ONE `Character` whose first scalar is the space. Character-based splitting then
/// treats the pair as whitespace and the mark silently vanishes, and a word boundary can hide.
/// An "orphan" extender, one that does not follow a letter or number (or an extender chain on
/// one), is replaced by U+FFFD, a standalone symbol that is never a letter, number or space, so
/// every parser splits the text exactly the way the tests do and the surrounding words stay
/// intact. Extenders after a letter or number are kept: Malayalam and Devanagari need them.
public enum TranscriptSanitiser {
    public static func sanitise(_ text: String) -> String {
        var result = String.UnicodeScalarView()
        var hasBase = false
        for scalar in text.unicodeScalars {
            if isExtender(scalar) {
                result.append(hasBase ? scalar : "\u{FFFD}")
            } else {
                result.append(scalar)
                let category = scalar.properties.generalCategory
                hasBase = isLetterOrNumber(category)
            }
        }
        return String(result)
    }

    private static func isLetterOrNumber(_ category: Unicode.GeneralCategory) -> Bool {
        switch category {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
            .decimalNumber, .letterNumber, .otherNumber:
            return true
        default:
            return false
        }
    }

    private static func isExtender(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .nonspacingMark, .spacingMark, .enclosingMark: return true
        default: break
        }
        switch scalar.value {
        case 0x200C, 0x200D, 0x1F3FB...0x1F3FF, 0xE0020...0xE007F: return true
        default: return false
        }
    }
}
