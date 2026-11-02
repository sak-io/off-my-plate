import Foundation

/// Bounds on everything a client can send. Checked at the facade boundary, before any arithmetic or
/// allocation that depends on the value (a trap kills the whole Wasm instance).
enum Limits {
    static let maxRequestBytes = 8 * 1024 * 1024
    /// Members per role in `household.create` (the core then checks the total, 1...12).
    static let maxMembersPerRole = 20
    static let maxItems = 200
    static let maxIDs = 100
    static let maxAbsences = 500
    static let maxTextCharacters = 20_000
    static let maxNameCharacters = 200
    /// Same bound the services apply to a pantry or shopping amount.
    static let maxAmount: Double = 1_000_000_000
    static let maxSearchResults = 20
    static let maxCookAmounts = 200
    /// Pasted text or file bytes for a Notes import (the parser itself reads at most 64 KiB of it).
    static let maxImportBytes = 256 * 1024
    static let maxBase64Characters = (maxImportBytes / 3 + 1) * 4
    static let maxRevision = 1_000_000
    static let maxIDCounter = 1_000_000_000
    static let earliestNow = Date(timeIntervalSince1970: 946_684_800)  // 2000-01-01T00:00:00Z
    static let latestNow = Date(timeIntervalSince1970: 4_102_444_800)  // 2100-01-01T00:00:00Z
    static let earliestYear = 2000
    static let latestYear = 2100

    static func require(_ condition: Bool, _ text: @autoclosure () -> String) throws {
        if !condition { throw FacadeError.invalid(text()) }
    }
}

/// Finds a repeated key inside one JSON object (the decoder would silently keep the last one). The input
/// must already be valid JSON.
enum DuplicateKeys {
    static func firstDuplicate(in data: Data) -> String? {
        let bytes = [UInt8](data)
        var isObject: [Bool] = []
        var expectingKey: [Bool] = []
        var keys: [Set<String>] = []
        var i = 0
        while i < bytes.count {
            switch bytes[i] {
            case UInt8(ascii: "\""):
                var j = i + 1
                while j < bytes.count, bytes[j] != UInt8(ascii: "\"") {
                    j += bytes[j] == UInt8(ascii: "\\") ? 2 : 1
                }
                if let top = isObject.last, top, expectingKey[expectingKey.count - 1], j < bytes.count {
                    let quoted = Data(bytes[i...j])
                    let key = (try? JSONDecoder().decode(String.self, from: quoted)) ?? String(decoding: quoted, as: UTF8.self)
                    if keys[keys.count - 1].contains(key) { return key }
                    keys[keys.count - 1].insert(key)
                    expectingKey[expectingKey.count - 1] = false
                }
                i = j
            case UInt8(ascii: "{"):
                isObject.append(true)
                expectingKey.append(true)
                keys.append([])
            case UInt8(ascii: "["):
                isObject.append(false)
                expectingKey.append(false)
                keys.append([])
            case UInt8(ascii: "}"), UInt8(ascii: "]"):
                if !isObject.isEmpty {
                    isObject.removeLast()
                    expectingKey.removeLast()
                    keys.removeLast()
                }
            case UInt8(ascii: ","):
                if let top = isObject.last, top { expectingKey[expectingKey.count - 1] = true }
            default:
                break
            }
            i += 1
        }
        return nil
    }
}
