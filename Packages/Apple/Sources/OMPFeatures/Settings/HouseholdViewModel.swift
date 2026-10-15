import Foundation
import Observation
import OMPDomain
import OMPServices

/// How a person's safety answer reads on S-30 (C-110a).
enum PersonStatus: Equatable, Sendable {
    case notAnswered
    case nothingToAvoid
    case avoids([String])
}

/// One hard rule as S-33 lists it.
struct RuleRow: Identifiable, Equatable, Sendable {
    let id: RuleID
    let item: String
    /// The person's display name, or nil for a household-wide rule.
    let who: String?
    let scope: RuleScope
}

/// The rules of one person (or everyone) on S-33.
struct RuleGroup: Identifiable {
    let title: String
    let rows: [RuleRow]
    var id: String { title }
}

/// One choice of the "Who is it for?" picker.
struct ScopeOption: Identifiable {
    let scope: RuleScope
    let title: String
    var id: RuleScope { scope }
}

/// The Household tab (S-30, S-31, S-33) and Delete all data (S-37 alert).
///
/// Every change goes through `SettingsBackend` (the services); this type never writes the
/// household itself. Hard rules are added and removed only by the methods below, which the
/// views call after the user's explicit confirmation ("Yes, save this", "Remove").
@MainActor
@Observable
final class HouseholdViewModel {
    let app: AppModel
    private let backend: (any SettingsBackend)?

    /// C-095 alert.
    var saveFailed = false
    var deleteFailed = false
    var isConfirmingDeleteAll = false
    private(set) var isBusy = false

    init(app: AppModel) {
        self.app = app
        self.backend = app.settingsBackend
    }

    var isAvailable: Bool { backend != nil }

    /// The alert text while a change or the delete failed (C-095 or the delete-all failure).
    var failureMessage: String? {
        if deleteFailed { return SettingsCopy.deleteFailed }
        return saveFailed ? SettingsCopy.saveFailed : nil
    }

    func dismissFailure() {
        saveFailed = false
        deleteFailed = false
    }

    // MARK: People (S-30)

    var members: [Member] { app.household?.activeMembers ?? [] }

    func status(of member: Member) -> PersonStatus {
        guard member.safetyStatus != .unasked else { return .notAnswered }
        let items = (app.household?.rules(covering: member.id) ?? []).map { label(for: $0.restriction) }
        return items.isEmpty ? .nothingToAvoid : .avoids(items)
    }

    func statusText(of member: Member) -> String {
        switch status(of: member) {
        case .notAnswered: return SettingsCopy.statusNotAnswered
        case .nothingToAvoid: return SettingsCopy.statusNothing
        case .avoids(let items): return SettingsCopy.statusAvoids(items.joined(separator: ", "))
        }
    }

    func label(for id: RestrictionID) -> String {
        backend?.restrictions.first { $0.id == id }.map(SafetyCopy.label(for:)) ?? id.rawValue
    }

    /// Roles follow the age group: toddlers and children are "Child n", the rest "Adult n"
    /// (teens count as adults for portions, C-011c).
    static func role(for band: AgeBand?) -> MemberRole {
        switch band {
        case .infant?, .toddler?, .child?: return .child
        case .teen?, .adult?, .senior?, nil: return .adult
        }
    }

    /// Age groups S-31 offers, in order (C-112).
    static let ageBands: [AgeBand?] = [nil, .toddler, .child, .teen, .adult, .senior]

    /// Adds a person (AC-16.1, AC-3.2). They start unasked, so the safety cover opens straight
    /// away for them; the approved plan stays usable.
    func addPerson(name: String, ageBand: AgeBand?) async -> Bool {
        guard let backend else { return false }
        // No reload here: the sheet reloads when it has closed (HouseholdTabView), so the safety
        // cover does not appear while the sheet is still on screen.
        return await perform(reload: false) {
            let member = try await backend.addMember(role: Self.role(for: ageBand), ageBand: ageBand)
            if !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // The name is optional: the person exists now, so a failed name must not report
                // the whole Add as failed (the safety question for them is next either way).
                do { try await backend.setName(name, for: member.id) } catch {
                    let kind = OMPLog.errorKind(error)
                    OMPLog.app.error("Naming the new person failed: \(kind, privacy: .public)")
                }
            }
        }
    }

    /// Saves the optional name and age group of an existing person (AC-16.1). A change between
    /// child and grown groups makes the safety question come back (AC-3.4).
    func savePerson(_ member: Member, name: String, ageBand: AgeBand?) async -> Bool {
        guard let backend else { return false }
        return await perform {
            if (member.name ?? "") != name {
                try await backend.setName(name, for: member.id)
            }
            if member.ageBand != ageBand {
                _ = try await backend.setAgeBand(ageBand, for: member.id)
            }
        }
    }

    /// Removes a person after the user confirmed (C-034b). The last person cannot be removed.
    func canRemove(_ member: Member) -> Bool { members.count > 1 }

    func removePerson(_ member: Member) async -> Bool {
        guard let backend, canRemove(member) else { return false }
        return await perform { try await backend.removeMember(member.id) }
    }

    // MARK: Safety rules (S-33)

    /// Hard rules grouped for the list: household-wide first, then per active member.
    var ruleRows: [RuleRow] {
        guard let household = app.household else { return [] }
        return household.rules.compactMap { rule in
            switch rule.scope {
            case .household:
                return RuleRow(id: rule.id, item: label(for: rule.restriction), who: nil, scope: rule.scope)
            case .member(let id):
                guard let member = household.member(id), !member.isDeleted else { return nil }
                return RuleRow(id: rule.id, item: label(for: rule.restriction), who: member.displayName, scope: rule.scope)
            }
        }
    }

    /// Groups in display order: "Everyone", then each person with rules.
    var ruleGroups: [RuleGroup] {
        let rows = ruleRows
        var groups: [RuleGroup] = []
        let everyone = rows.filter { $0.who == nil }
        if !everyone.isEmpty { groups.append(RuleGroup(title: SettingsCopy.everyone, rows: everyone)) }
        for member in members {
            let mine = rows.filter { $0.scope == .member(member.id) }
            if !mine.isEmpty { groups.append(RuleGroup(title: member.displayName, rows: mine)) }
        }
        return groups
    }

    /// The catalog restrictions the add sheet offers as chips.
    var restrictionChoices: [Restriction] { backend?.restrictions ?? [] }

    /// What typed text names (catalog matches and words that match nothing).
    func readSafetyText(_ text: String) -> SafetyTextReading {
        backend?.readSafetyText(text) ?? SafetyTextReading(restrictions: [], unrecognised: [text])
    }

    /// Who a new rule can be for: everyone, or one person.
    var scopeOptions: [ScopeOption] {
        var options = [ScopeOption(scope: .household, title: SettingsCopy.everyone)]
        for member in members {
            options.append(ScopeOption(scope: .member(member.id), title: member.displayName))
        }
        return options
    }

    func scopeTitle(_ scope: RuleScope) -> String {
        scopeOptions.first { $0.scope == scope }?.title ?? SettingsCopy.everyone
    }

    /// The plain-language summary the plan card and the 180-day card show (C-061, C-040a).
    var safetySummary: String? {
        guard let household = app.household else { return nil }
        return SafetySummary.text(
            household: household, label: { self.label(for: $0) })
    }

    /// Saves the confirmed new rules (the user pressed "Yes, save this"). Rules already in
    /// force for the same scope are skipped. The service re-validates open plans (AC-3.5).
    func addRules(_ requests: [RuleRequest]) async -> Bool {
        guard let backend else { return false }
        let existing = Set(
            (app.household?.rules ?? []).map { RuleRequest(restriction: $0.restriction, scope: $0.scope) })
        let fresh = requests.filter { !existing.contains($0) }
        guard !fresh.isEmpty else { return true }
        return await perform { try await backend.addRules(fresh) }
    }

    /// Removes a rule after the user confirmed C-036.
    func removeRule(_ row: RuleRow) async -> Bool {
        guard let backend else { return false }
        return await perform { try await backend.removeRule(row.id) }
    }

    /// "Yes, still correct" on the 180-day card (G3).
    func reconfirm() async -> Bool {
        guard let backend else { return false }
        return await perform { try await backend.reconfirmSafety() }
    }

    // MARK: Delete all data (AC-16.2)

    /// Runs after the confirmation alert. On success the app model forgets the household, which
    /// restarts onboarding at S-01; on failure nothing else changes and the alert says so.
    func deleteAll() async {
        guard let backend, !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            try await backend.deleteAllData()
        } catch is StorePurgeError {
            // Every record is gone: restart onboarding, and keep the incomplete purge visible
            // to the app (log and flag) instead of leaving the user on empty tabs.
            OMPLog.app.error("Delete all data: the store file could not be rewritten")
            await app.dataWasDeleted(purgeIncomplete: true)
            return
        } catch {
            let kind = OMPLog.errorKind(error)
            OMPLog.app.error("Delete all data failed: \(kind, privacy: .public)")
            deleteFailed = true
            // Part of the data may be gone: show what is really stored.
            await app.refresh()
            return
        }
        await app.dataWasDeleted()
    }

    // MARK: Plumbing

    /// Runs `work`, then reloads the household and the gate. A failure shows C-095.
    private func perform(reload: Bool = true, _ work: () async throws -> Void) async -> Bool {
        guard !isBusy else { return false }
        isBusy = true
        defer { isBusy = false }
        do {
            try await work()
        } catch {
            let kind = OMPLog.errorKind(error)
            OMPLog.app.error("Household change failed: \(kind, privacy: .public)")
            saveFailed = true
            await app.refresh()
            return false
        }
        if reload { await app.refresh() }
        return true
    }
}

/// The one-line description of what the household avoids.
enum SafetySummary {
    /// "Adult 1 avoids Peanuts; everyone avoids Beef", or nil when there are no rules.
    static func text(household: Household, label: (RestrictionID) -> String) -> String? {
        var parts: [String] = []
        let everyone = household.rules.filter { $0.scope == .household }.map { label($0.restriction) }
        for member in household.activeMembers {
            let own = household.rules
                .filter { $0.scope == .member(member.id) }
                .map { label($0.restriction) }
            if !own.isEmpty {
                parts.append(SettingsCopy.summaryAvoids(who: member.displayName, items: own.joined(separator: ", ")))
            }
        }
        if !everyone.isEmpty {
            parts.append(SettingsCopy.summaryAvoids(who: SettingsCopy.summaryEveryone, items: everyone.joined(separator: ", ")))
        }
        return parts.isEmpty ? nil : parts.joined(separator: "; ")
    }
}
