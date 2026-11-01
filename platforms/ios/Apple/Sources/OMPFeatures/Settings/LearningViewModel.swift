import Foundation
import Observation
import OMPDomain
import OMPServices

/// Plain-language text for soft facts. Only soft statements exist (AC-12.4), so nothing here can
/// describe an allergy or a hard restriction.
struct FactText {
    let recipeTitle: (RecipeID) -> String?
    let ingredientName: (IngredientID) -> String?

    /// "You cook South Indian food", "You often swap out okra", ...
    func sentence(_ statement: FactStatement) -> String {
        switch statement {
        case .cuisineAffinity(let id):
            return SettingsCopy.likesCuisine(SettingsCopy.cuisine(id))
        case .dislikesRecipe(let id):
            return SettingsCopy.skipsRecipe(recipeTitle(id) ?? SettingsCopy.unknownItem)
        case .dislikesIngredient(let id):
            return SettingsCopy.swapsOut(ingredientName(id)?.lowercased() ?? SettingsCopy.unknownItem)
        case .prefersQuickWeekday:
            return SettingsCopy.quickWeekday
        case .staple(let id):
            return SettingsCopy.keepsStocked(ingredientName(id)?.lowercased() ?? SettingsCopy.unknownItem)
        case .favouriteRecipe(let id):
            return SettingsCopy.likesRecipe(recipeTitle(id) ?? SettingsCopy.unknownItem)
        }
    }

    /// C-153: where the fact came from. ASSUMPTION: the service does not expose event counts,
    /// so the "{n}" of the design copy is left out.
    func origin(of fact: Fact) -> String {
        switch fact.origin {
        case .stated: return SettingsCopy.originSaid
        case .confirmed: return SettingsCopy.originConfirmed
        case .appDefault: return SettingsCopy.originDefault
        case .inferred:
            switch fact.statement {
            case .dislikesRecipe, .dislikesIngredient, .prefersQuickWeekday: return SettingsCopy.originSwaps
            case .favouriteRecipe, .cuisineAffinity: return SettingsCopy.originCooked
            case .staple: return SettingsCopy.originLists
            }
        }
    }
}

/// The four groups of S-35 (C-150a).
enum LearnedSection: CaseIterable, Hashable, Sendable {
    case told, confirmed, noticed, guesses

    var title: String {
        switch self {
        case .told: return SettingsCopy.sectionTold
        case .confirmed: return SettingsCopy.sectionConfirmed
        case .noticed: return SettingsCopy.sectionNoticed
        case .guesses: return SettingsCopy.sectionGuesses
        }
    }

    var identifier: String {
        switch self {
        case .told: return "told"
        case .confirmed: return "confirmed"
        case .noticed: return "noticed"
        case .guesses: return "guesses"
        }
    }

    static func of(_ fact: Fact) -> LearnedSection {
        switch fact.origin {
        case .stated: return .told
        case .confirmed: return .confirmed
        case .inferred: return .noticed
        case .appDefault: return .guesses
        }
    }
}

/// The facts of one S-35 section.
struct LearnedGroup: Identifiable {
    let section: LearnedSection
    let facts: [Fact]
    var id: LearnedSection { section }
}

/// One choice of the "Applies to" picker.
struct SubjectOption: Identifiable {
    let subject: FactSubject
    let title: String
    var id: FactSubject { subject }
}

/// "What I've learned" and the fact sheet (S-35, S-36; AC-12.5).
@MainActor
@Observable
final class LearningViewModel {
    enum Phase: Equatable { case loading, loaded, failed }

    /// Confidence from which an inferred fact reads "Likely" (below it: "Maybe").
    /// ASSUMPTION: 0.6, i.e. about three events' worth of weight.
    static let likelyConfidence = 0.6

    private let app: AppModel
    private let backend: (any SettingsBackend)?
    private(set) var phase: Phase = .loading
    private(set) var facts: [Fact] = []
    var saveFailed = false
    /// The fact the user asked to forget; the confirmation alert (C-154) shows while set.
    var pendingForget: Fact?

    init(app: AppModel) {
        self.app = app
        self.backend = app.settingsBackend
    }

    var text: FactText {
        let backend = self.backend
        return FactText(
            recipeTitle: { backend?.recipeTitle($0) }, ingredientName: { backend?.ingredientName($0) })
    }

    func load() async {
        guard let backend else {
            phase = .failed
            return
        }
        do {
            facts = try await backend.learned()
            phase = .loaded
        } catch {
            let kind = OMPLog.errorKind(error)
            OMPLog.app.error("Loading what was learned failed: \(kind, privacy: .public)")
            phase = .failed
        }
    }

    var isEmpty: Bool { facts.isEmpty }

    /// Sections that have facts, in display order; facts inside a section keep the stored order.
    var sections: [LearnedGroup] {
        LearnedSection.allCases.compactMap { section -> LearnedGroup? in
            let inSection = facts.filter { LearnedSection.of($0) == section }
            return inSection.isEmpty ? nil : LearnedGroup(section: section, facts: inSection)
        }
    }

    func sentence(_ fact: Fact) -> String { text.sentence(fact.statement) }

    /// "Likely" / "Maybe" for noticed facts only (C-150b).
    func confidenceWord(_ fact: Fact) -> String? {
        guard fact.origin == .inferred else { return nil }
        return fact.confidence >= Self.likelyConfidence ? SettingsCopy.likely : SettingsCopy.maybe
    }

    /// "That's right" is offered on noticed facts that are not confirmed yet.
    func canQuickConfirm(_ fact: Fact) -> Bool {
        fact.origin == .inferred && (fact.status == .proposed || fact.status == .active)
    }

    func fact(_ id: FactID) -> Fact? { facts.first { $0.id == id } }

    // MARK: Actions

    /// "That's right": the same as Yes on the reflect-back card.
    func thatsRight(_ fact: Fact) async {
        await change { try await $0.answerReflectBack(fact.key, .yes) }
    }

    func requestForget(_ fact: Fact) {
        pendingForget = fact
    }

    /// Forgets `fact`; the caller asked for confirmation first (C-154).
    func forget(_ fact: Fact) async {
        await change { try await $0.forget(fact.id) }
    }

    /// Saves who the fact applies to and, for recipes, how strongly. The result is always a
    /// soft statement that the user stated (AC-12.4).
    func save(_ fact: Fact, subject: FactSubject, statement: FactStatement) async {
        await change {
            try await $0.restate(fact.id, subject: subject, statement: statement == fact.statement ? nil : statement)
        }
    }

    /// People the "Applies to" picker offers.
    var subjects: [SubjectOption] {
        var options = [SubjectOption(subject: .household, title: SettingsCopy.everyone)]
        for member in app.household?.activeMembers ?? [] {
            options.append(SubjectOption(subject: .member(member.id), title: member.displayName))
        }
        return options
    }

    /// The prefer/avoid pair of a recipe statement; nil for statements that have no pair.
    static func strengthOptions(for statement: FactStatement) -> (prefer: FactStatement, avoid: FactStatement)? {
        switch statement {
        case .dislikesRecipe(let id), .favouriteRecipe(let id):
            return (prefer: .favouriteRecipe(id), avoid: .dislikesRecipe(id))
        case .cuisineAffinity, .dislikesIngredient, .prefersQuickWeekday, .staple:
            return nil
        }
    }

    private func change(_ work: (any SettingsBackend) async throws -> Void) async {
        guard let backend else { return }
        do {
            try await work(backend)
        } catch {
            let kind = OMPLog.errorKind(error)
            OMPLog.app.error("Changing a learned fact failed: \(kind, privacy: .public)")
            saveFailed = true
        }
        await load()
    }
}

/// The reflect-back card (C-100 to C-103; AC-12.2, AC-12.3): at most one, never shown while a
/// safety card is waiting (safety cards win).
@MainActor
@Observable
final class ReflectBackModel {
    private let app: AppModel
    private let backend: (any SettingsBackend)?
    private let announce: @MainActor (String) -> Void
    private(set) var fact: Fact?
    private(set) var isAnswering = false

    /// - Parameter announce: shows the after-answer message (C-101 to C-103), for example as a toast.
    init(app: AppModel, announce: @escaping @MainActor (String) -> Void) {
        self.app = app
        self.backend = app.settingsBackend
        self.announce = announce
    }

    /// C-100's question for the current card.
    var question: String? {
        guard let fact, let backend else { return nil }
        let text = FactText(
            recipeTitle: { backend.recipeTitle($0) }, ingredientName: { backend.ingredientName($0) })
        return SettingsCopy.reflectQuestion(text.sentence(fact.statement))
    }

    /// Asks the learner for the card to show now. Nothing shows while safety blocks planning.
    func load() async {
        guard let backend, app.gateStatus == .clear else {
            fact = nil
            return
        }
        do {
            fact = try await backend.nextReflectBack()
        } catch {
            let kind = OMPLog.errorKind(error)
            OMPLog.app.error("Loading the reflect-back card failed: \(kind, privacy: .public)")
            fact = nil
        }
    }

    func answer(_ answer: ReflectBackAnswer) async {
        guard let backend, let current = fact, !isAnswering else { return }
        isAnswering = true
        defer { isAnswering = false }
        do {
            try await backend.answerReflectBack(current.key, answer)
        } catch {
            let kind = OMPLog.errorKind(error)
            OMPLog.app.error("Saving the reflect-back answer failed: \(kind, privacy: .public)")
            return
        }
        fact = nil
        announce(SettingsCopy.afterAnswer(answer))
    }
}
