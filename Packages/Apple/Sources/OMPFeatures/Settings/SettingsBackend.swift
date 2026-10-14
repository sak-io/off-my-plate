import Foundation
import OMPDomain
import OMPServices

/// What typed text said about foods to avoid: catalog restrictions that matched, and words that
/// did not (those can never count as "checked", AC-2.4).
public struct SafetyTextReading: Sendable, Hashable {
    public var restrictions: [RestrictionID]
    public var unrecognised: [String]

    public init(restrictions: [RestrictionID], unrecognised: [String]) {
        self.restrictions = restrictions
        self.unrecognised = unrecognised
    }
}

/// What the Household tab and the learning screens need from the services (task T27). The live
/// implementation wraps `HouseholdService`, `SafetyService`, `LearningService` and the delete-all
/// path; tests can use it over in-memory repositories.
///
/// Hard rules change only through `addRules` / `removeRule` / `reconfirmSafety`, which are the
/// `SafetyService` calls; the screens call them only after the user's explicit confirmation.
/// Learning calls can only write soft `FactStatement`s.
public protocol SettingsBackend: Sendable {
    /// The restriction catalog the add-rule sheet offers.
    var restrictions: [Restriction] { get }

    // Household (AC-16.1)
    func addMember(role: MemberRole, ageBand: AgeBand?) async throws -> Member
    func removeMember(_ id: MemberID) async throws
    /// Returns whether the member is `unasked` again (AC-3.4).
    func setAgeBand(_ band: AgeBand?, for id: MemberID) async throws -> Bool
    func setName(_ name: String?, for id: MemberID) async throws

    // Safety (AC-3.5, G3)
    func readSafetyText(_ text: String) -> SafetyTextReading
    func addRules(_ requests: [RuleRequest]) async throws
    func removeRule(_ id: RuleID) async throws
    func reconfirmSafety() async throws

    // Learning (AC-12.2, AC-12.3, AC-12.5)
    func learned() async throws -> [Fact]
    func nextReflectBack() async throws -> Fact?
    func answerReflectBack(_ key: FactKey, _ answer: ReflectBackAnswer) async throws
    func forget(_ id: FactID) async throws
    func restate(_ id: FactID, subject: FactSubject, statement: FactStatement?) async throws
    /// Recipe and ingredient names for fact sentences (display only).
    func recipeTitle(_ id: RecipeID) -> String?
    func ingredientName(_ id: IngredientID) -> String?

    /// "Delete all data" (AC-16.2): every record, the processed-import ids, the counters, the
    /// inbox and the store's on-disk traces.
    func deleteAllData() async throws
}

/// The services as the Household tab uses them.
public final class LiveSettingsBackend: SettingsBackend {
    private let context: ServiceContext
    private let households: HouseholdService
    private let safetyService: SafetyService
    private let learning: LearningService
    private let parser: SafetyTextParser
    private let dataService: DataService?
    private let eraseStore: (@Sendable () async throws -> Void)?

    /// - Parameters:
    ///   - parser: turns typed text into catalog restrictions (T16).
    ///   - counters: where learning prompt counters go (ADR 0014); `nil` records none.
    ///   - dataService: removes repositories, imports, counters and the inbox (T19). When `nil`
    ///     only the repositories are emptied (UI tests and previews).
    ///   - eraseStore: the store-level erase that also rewrites the SQLite file and truncates
    ///     its write-ahead log (`PersistenceStore.eraseAllData`, AC-16.2); `nil` for in-memory.
    public init(
        context: ServiceContext, parser: SafetyTextParser, counters: (any CounterStore)? = nil,
        dataService: DataService? = nil, eraseStore: (@Sendable () async throws -> Void)? = nil
    ) {
        self.context = context
        self.households = HouseholdService(context: context)
        self.safetyService = SafetyService(context: context)
        self.learning = LearningService(context: context, counters: counters)
        self.parser = parser
        self.dataService = dataService
        self.eraseStore = eraseStore
    }

    public var restrictions: [Restriction] { context.library.restrictions }

    public func addMember(role: MemberRole, ageBand: AgeBand?) async throws -> Member {
        try await households.addMember(role: role, ageBand: ageBand)
    }

    public func removeMember(_ id: MemberID) async throws {
        _ = try await households.removeMember(id)
    }

    public func setAgeBand(_ band: AgeBand?, for id: MemberID) async throws -> Bool {
        try await households.setAgeBand(band, for: id)
    }

    public func setName(_ name: String?, for id: MemberID) async throws {
        _ = try await households.setName(name, for: id)
    }

    public func readSafetyText(_ text: String) -> SafetyTextReading {
        var matched: [RestrictionID] = []
        var unrecognised: [String] = []
        for candidate in parser.parse(text) {
            switch candidate {
            case .restriction(let id, _, _):
                if context.library.restriction(id) != nil {
                    matched.append(id)
                } else {
                    unrecognised.append(id.rawValue)
                }
            case .unmapped(let word, _):
                unrecognised.append(word)
            }
        }
        return SafetyTextReading(restrictions: matched, unrecognised: unrecognised)
    }

    public func addRules(_ requests: [RuleRequest]) async throws {
        for request in requests {
            _ = try await safetyService.addRule(request)
        }
    }

    public func removeRule(_ id: RuleID) async throws {
        _ = try await safetyService.removeRule(id)
    }

    public func reconfirmSafety() async throws {
        _ = try await safetyService.reconfirm()
    }

    public func learned() async throws -> [Fact] {
        try await learning.learned()
    }

    public func nextReflectBack() async throws -> Fact? {
        try await learning.nextReflectBack()
    }

    public func answerReflectBack(_ key: FactKey, _ answer: ReflectBackAnswer) async throws {
        _ = try await learning.answerReflectBack(key, answer)
    }

    public func forget(_ id: FactID) async throws {
        _ = try await learning.forget(id)
    }

    public func restate(_ id: FactID, subject: FactSubject, statement: FactStatement?) async throws {
        _ = try await learning.restate(id, subject: subject, statement: statement)
    }

    public func recipeTitle(_ id: RecipeID) -> String? {
        context.library.recipesByID[id]?.title
    }

    public func ingredientName(_ id: IngredientID) -> String? {
        context.library.ingredientsByID[id]?.name
    }

    public func deleteAllData() async throws {
        if let dataService {
            try await dataService.deleteAll()
        } else {
            try await context.repositories.deleteAll()
        }
        try await eraseStore?()
    }
}
