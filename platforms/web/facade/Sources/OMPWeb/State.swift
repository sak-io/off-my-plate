import Foundation
import OMPDomain
import OMPServices

enum SnapshotFormat {
    static let name = "omp-web-state"
    static let version = 1
}

/// The full state of a session, versioned, so the browser can persist it (IndexedDB/OPFS) and hand it
/// back. Every collection is exported in repository (insertion) order, so the bytes are stable.
struct StateSnapshot: Codable, Sendable {
    var format: String
    var version: Int
    var contentVersion: String
    var idCounter: Int
    var household: Household?
    var mealPlans: [MealPlan]
    var pantry: [PantryItem]
    var shopping: [ShoppingItem]
    var cookLogs: [CookLog]
    var facts: [Fact]
    var learningEvents: [LearningEvent]
    var promptStates: [PromptState]
}

struct SnapshotView: Encodable {
    var snapshot: StateSnapshot
}

struct ImportedView: Encodable {
    var imported: Bool
    var recheck: RecheckView
}

extension FacadeSession {
    func exportState(_ engine: Engine) async throws -> Data {
        let repositories = engine.repositories
        let snapshot = StateSnapshot(
            format: SnapshotFormat.name, version: SnapshotFormat.version,
            contentVersion: engine.context.library.contentVersion, idCounter: engine.ids.current,
            household: try await repositories.household.fetch(), mealPlans: try await repositories.mealPlans.fetchAll(),
            pantry: try await repositories.pantry.fetchAll(), shopping: try await repositories.shopping.fetchAll(),
            cookLogs: try await repositories.cookLogs.fetchAll(), facts: try await repositories.facts.fetchAll(),
            learningEvents: try await repositories.learningEvents.fetchAll(),
            promptStates: try await repositories.promptStates.fetchAll())
        return try CanonicalJSON.encode(SnapshotView(snapshot: snapshot))
    }

    /// Replaces the whole state with a snapshot. Everything is validated and loaded into a NEW set of
    /// repositories first; the session switches to them only after that and the R1 re-check succeeded,
    /// so a rejected or failing import leaves the current state untouched.
    func importState(_ request: Request, content: SeedContent) async throws -> Data {
        guard let raw = request.args["snapshot"] else { throw FacadeError.badRequest("Missing argument \"snapshot\".") }
        // The version is checked before the rest of the document is decoded, so a newer file is
        // reported as such rather than as garbage.
        guard case .object = raw, raw["format"]?.stringValue == SnapshotFormat.name else {
            throw FacadeError("invalid_state", "The data is not an OffMyPlate state snapshot.")
        }
        guard case .int(let version)? = raw["version"], version == Int64(SnapshotFormat.version) else {
            throw FacadeError("unsupported_state_version", "This state was written by another version of the app.")
        }
        let snapshot: StateSnapshot
        do {
            snapshot = try CanonicalJSON.decoder().decode(StateSnapshot.self, from: JSONEncoder().encode(raw))
        } catch {
            throw FacadeError("invalid_state", "The state snapshot is damaged.")
        }
        try Self.validate(snapshot)

        let repositories = Repositories.inMemory()
        if let household = snapshot.household { try await repositories.household.replace(with: household) }
        try await repositories.mealPlans.save(snapshot.mealPlans)
        for item in snapshot.pantry { try await repositories.pantry.save(item) }
        for item in snapshot.shopping { try await repositories.shopping.save(item) }
        for log in snapshot.cookLogs { try await repositories.cookLogs.save(log) }
        for fact in snapshot.facts { try await repositories.facts.save(fact) }
        for event in snapshot.learningEvents { try await repositories.learningEvents.save(event) }
        for state in snapshot.promptStates { try await repositories.promptStates.save(state) }

        let fresh = Engine(
            repositories: repositories, clock: clock, ids: IDSource(counter: snapshot.idCounter), content: content)
        // R1 on load (also repairs a re-check interrupted by a closed tab, and handles a new seed version).
        var outcome = try await fresh.safety.recheckOpenPlans()
        if let library = try await fresh.safety.recheckIfLibraryChanged() { outcome = library }
        replaceEngine(fresh)
        return try CanonicalJSON.encode(ImportedView(imported: true, recheck: RecheckView(outcome)))
    }

    /// Structural checks a decoder cannot make. Importing never bypasses the approval rules: an approved
    /// plan must carry an approval record whose hash matches its content, and a draft or discarded plan
    /// must not carry one.
    static func validate(_ snapshot: StateSnapshot) throws {
        func fail(_ text: String) -> FacadeError { FacadeError("invalid_state", text) }
        guard snapshot.idCounter >= 0 else { throw fail("The id counter is negative.") }
        guard Set(snapshot.mealPlans.map(\.id)).count == snapshot.mealPlans.count else { throw fail("Duplicate plan ids.") }
        guard Set(snapshot.pantry.map(\.id)).count == snapshot.pantry.count else { throw fail("Duplicate pantry ids.") }
        guard Set(snapshot.shopping.map(\.id)).count == snapshot.shopping.count else { throw fail("Duplicate shopping ids.") }
        guard Set(snapshot.cookLogs.map(\.id)).count == snapshot.cookLogs.count else { throw fail("Duplicate cook log ids.") }
        guard Set(snapshot.facts.map(\.id)).count == snapshot.facts.count else { throw fail("Duplicate fact ids.") }
        if let household = snapshot.household {
            guard !household.members.isEmpty else { throw fail("The household has no members.") }
            guard Set(household.members.map(\.id)).count == household.members.count else { throw fail("Duplicate member ids.") }
        }
        for plan in snapshot.mealPlans {
            switch plan.status {
            case PlanStatus.approved:
                guard let approval = plan.approval, approval.contentHash == plan.contentHash else {
                    throw fail("An approved plan does not match its approval record.")
                }
            case PlanStatus.draft, PlanStatus.discarded:
                guard plan.approval == nil else { throw fail("A plan that was not approved carries an approval record.") }
            case PlanStatus.superseded:
                break
            }
        }
    }
}
