import Foundation
import OMPDomain

/// Small helpers shared by the record mappers.
enum Mapping {
    /// `raw` if it is non-empty; empty ids are never written or read.
    static func id(_ raw: String, entity: String) throws -> String {
        guard !raw.isEmpty else { throw PersistenceError.emptyIdentifier(entity: entity) }
        return raw
    }

    /// The raw value of a typed id, refusing an empty one.
    static func raw<Tag>(_ id: EntityID<Tag>, entity: String) throws -> String {
        try Mapping.id(id.rawValue, entity: entity)
    }

    /// A typed id from a stored string, refusing an empty one.
    static func entityID<Tag>(_ raw: String, entity: String) throws -> EntityID<Tag> {
        EntityID(try Mapping.id(raw, entity: entity))
    }

    /// An optional typed id from an optional stored string (empty is an error, nil is nil).
    static func optionalEntityID<Tag>(_ raw: String?, entity: String) throws -> EntityID<Tag>? {
        guard let raw else { return nil }
        return EntityID(try Mapping.id(raw, entity: entity))
    }

    /// A string-backed enum from its stored raw value.
    static func value<Value: RawRepresentable>(
        _ type: Value.Type, _ raw: String, entity: String, field: String
    ) throws -> Value where Value.RawValue == String {
        guard let value = Value(rawValue: raw) else {
            throw PersistenceError.invalidValue(entity: entity, field: field, value: raw)
        }
        return value
    }

    /// An optional string-backed enum from an optional stored raw value.
    static func optionalValue<Value: RawRepresentable>(
        _ type: Value.Type, _ raw: String?, entity: String, field: String
    ) throws -> Value? where Value.RawValue == String {
        guard let raw else { return nil }
        return try value(type, raw, entity: entity, field: field)
    }

    /// A calendar day from its ISO 8601 string.
    static func localDate(_ raw: String, entity: String, field: String) throws -> LocalDate {
        guard let date = LocalDate(isoString: raw) else {
            throw PersistenceError.invalidValue(entity: entity, field: field, value: raw)
        }
        return date
    }

    /// An optional calendar day from an optional ISO 8601 string.
    static func optionalLocalDate(_ raw: String?, entity: String, field: String) throws -> LocalDate? {
        guard let raw else { return nil }
        return try localDate(raw, entity: entity, field: field)
    }

    /// A set of string-backed enums as a sorted array (stable storage, ADR 0003).
    static func sortedRaw<Value: RawRepresentable>(_ values: Set<Value>) -> [String] where Value.RawValue == String {
        values.map(\.rawValue).sorted()
    }

    /// The deterministic JSON encoder for every blob OMPData writes.
    static func jsonEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

/// A fact subject and statement flattened into four columns, shared by `FactRecord` and the
/// `reflectBackAnswered` learning event (both store a `FactKey`).
struct FactKeyColumns: Hashable {
    var subjectKind: String
    var subjectMemberId: String?
    var statementKind: String
    var statementRef: String?

    init(subjectKind: String, subjectMemberId: String?, statementKind: String, statementRef: String?) {
        self.subjectKind = subjectKind
        self.subjectMemberId = subjectMemberId
        self.statementKind = statementKind
        self.statementRef = statementRef
    }

    init(subject: FactSubject, statement: FactStatement, entity: String) throws {
        switch subject {
        case .household:
            subjectKind = "household"
            subjectMemberId = nil
        case .member(let id):
            subjectKind = "member"
            subjectMemberId = try Mapping.raw(id, entity: entity)
        }
        switch statement {
        case .cuisineAffinity(let id):
            statementKind = "cuisineAffinity"
            statementRef = try Mapping.raw(id, entity: entity)
        case .dislikesRecipe(let id):
            statementKind = "dislikesRecipe"
            statementRef = try Mapping.raw(id, entity: entity)
        case .dislikesIngredient(let id):
            statementKind = "dislikesIngredient"
            statementRef = try Mapping.raw(id, entity: entity)
        case .prefersQuickWeekday:
            statementKind = "prefersQuickWeekday"
            statementRef = nil
        case .staple(let id):
            statementKind = "staple"
            statementRef = try Mapping.raw(id, entity: entity)
        case .favouriteRecipe(let id):
            statementKind = "favouriteRecipe"
            statementRef = try Mapping.raw(id, entity: entity)
        }
    }

    func subject(entity: String) throws -> FactSubject {
        switch subjectKind {
        case "household":
            return .household
        case "member":
            return .member(try Mapping.entityID(subjectMemberId ?? "", entity: entity))
        default:
            throw PersistenceError.invalidValue(entity: entity, field: "subjectKind", value: subjectKind)
        }
    }

    func statement(entity: String) throws -> FactStatement {
        func ref<Tag>() throws -> EntityID<Tag> {
            try Mapping.entityID(statementRef ?? "", entity: entity)
        }
        switch statementKind {
        case "cuisineAffinity": return .cuisineAffinity(try ref())
        case "dislikesRecipe": return .dislikesRecipe(try ref())
        case "dislikesIngredient": return .dislikesIngredient(try ref())
        case "prefersQuickWeekday": return .prefersQuickWeekday
        case "staple": return .staple(try ref())
        case "favouriteRecipe": return .favouriteRecipe(try ref())
        default:
            throw PersistenceError.invalidValue(entity: entity, field: "statementKind", value: statementKind)
        }
    }
}
