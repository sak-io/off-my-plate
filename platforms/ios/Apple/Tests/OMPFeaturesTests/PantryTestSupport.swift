import Foundation
import OMPDomain
import OMPServices

@testable import OMPFeatures

/// A scripted `PantryBackend`. Tests run on the main actor one at a time, so the unchecked
/// Sendable conformance is safe here.
final class FakePantryBackend: PantryBackend, @unchecked Sendable {
    var stored: [PantryItem]
    var catalog: [IngredientID: IngredientDefaults] = [
        "rice": IngredientDefaults(name: "Rice", unit: .gram, location: .shelf),
        "milk": IngredientDefaults(name: "Milk", unit: .litre, location: .fridge),
        "egg": IngredientDefaults(name: "Egg", unit: .piece, location: .fridge),
        "onion": IngredientDefaults(name: "Onion", unit: .piece, location: .shelf),
    ]
    var parseResult = SpokenCommandParseResult(commands: [], unparsed: [], wasTruncated: false)
    var proposal = CookProposal(mealTitle: "Rajma chawal", lines: [])
    var failure: (any Error)?
    var cookFailure: (any Error)?

    private(set) var added: [PantryItemInput] = []
    private(set) var updated: [(PantryItemID, PantryItemInput)] = []
    private(set) var deleted: [PantryItemID] = []
    private(set) var reconfirmed: [PantryItemID] = []
    private(set) var confirmed: [[SpokenCommand]] = []
    private(set) var cookedAmounts: [[CookAmount]] = []
    private(set) var parsedTranscripts: [String] = []

    init(stored: [PantryItem] = []) {
        self.stored = stored
    }

    func items() async throws -> [PantryItem] {
        if let failure { throw failure }
        return stored
    }

    func searchIngredients(_ query: String) -> [IngredientResolver.Candidate] {
        catalog.filter { $0.value.name.localizedCaseInsensitiveContains(query) }
            .sorted { $0.key < $1.key }
            .map { IngredientResolver.Candidate(ingredientId: $0.key, name: $0.value.name, matchedTerm: $0.value.name, kind: .prefix) }
    }

    func defaults(for id: IngredientID) -> IngredientDefaults? { catalog[id] }

    func add(_ input: PantryItemInput) async throws -> PantryItem {
        if let failure { throw failure }
        added.append(input)
        let item = PantryItem(
            id: PantryItemID("new-\(added.count)"), item: reference(input), quantity: input.quantity,
            unit: input.unit, location: input.location, expiresOn: input.expiresOn, lastConfirmedAt: fixtureNow,
            source: .manual)
        stored.append(item)
        return item
    }

    func update(_ id: PantryItemID, with input: PantryItemInput) async throws -> PantryItem {
        if let failure { throw failure }
        updated.append((id, input))
        guard let index = stored.firstIndex(where: { $0.id == id }) else { throw ServiceError.pantryItemNotFound(id) }
        stored[index].item = reference(input)
        stored[index].quantity = input.quantity
        stored[index].unit = input.unit
        stored[index].location = input.location
        stored[index].expiresOn = input.expiresOn
        stored[index].lastConfirmedAt = fixtureNow
        return stored[index]
    }

    func reconfirm(_ id: PantryItemID) async throws {
        if let failure { throw failure }
        reconfirmed.append(id)
        if let index = stored.firstIndex(where: { $0.id == id }) { stored[index].lastConfirmedAt = fixtureNow }
    }

    func delete(_ id: PantryItemID) async throws {
        if let failure { throw failure }
        deleted.append(id)
        stored.removeAll { $0.id == id }
    }

    func parseSpoken(_ transcript: String) -> SpokenCommandParseResult {
        parsedTranscripts.append(transcript)
        return parseResult
    }

    func confirmVoice(_ commands: [SpokenCommand]) async throws -> VoiceOutcome {
        if let failure { throw failure }
        confirmed.append(commands)
        var outcome = VoiceOutcome()
        for case .add(let items) in commands {
            for spoken in items {
                let quantity = spoken.quantity ?? Quantity(1, .piece)
                let item = PantryItem(
                    id: PantryItemID("voice-\(stored.count)"), item: .ingredient(spoken.match.ingredientId),
                    quantity: quantity.amount, unit: quantity.unit, location: .shelf, lastConfirmedAt: fixtureNow,
                    source: .voice)
                stored.append(item)
                outcome.added.append(item)
            }
        }
        return outcome
    }

    func cookProposal(plan: MealPlanID, meal: PlannedMealID) async throws -> CookProposal {
        if let cookFailure { throw cookFailure }
        return proposal
    }

    func markCooked(plan: MealPlanID, meal: PlannedMealID, amounts: [CookAmount]) async throws {
        if let cookFailure { throw cookFailure }
        cookedAmounts.append(amounts)
    }

    private func reference(_ input: PantryItemInput) -> PantryItemRef {
        input.ingredientId.map(PantryItemRef.ingredient) ?? .freeText(input.name)
    }
}

enum PantryFixtureError: Error { case boom }

func pantryItem(
    _ id: String, _ ingredient: String, _ quantity: Double, _ unit: MeasureUnit, _ location: StorageLocation,
    confirmedDaysAgo: Int = 0, expiresOn: LocalDate? = nil
) -> PantryItem {
    PantryItem(
        id: PantryItemID(id), item: .ingredient(IngredientID(ingredient)), quantity: quantity, unit: unit,
        location: location, expiresOn: expiresOn,
        lastConfirmedAt: fixtureNow.addingTimeInterval(-Double(confirmedDaysAgo) * 86_400), source: .manual)
}

func freeTextItem(_ id: String, _ text: String) -> PantryItem {
    PantryItem(
        id: PantryItemID(id), item: .freeText(text), quantity: 1, unit: .piece, location: .shelf,
        lastConfirmedAt: fixtureNow, source: .manual)
}

func candidate(_ id: String, _ name: String) -> IngredientResolver.Candidate {
    IngredientResolver.Candidate(ingredientId: IngredientID(id), name: name, matchedTerm: name.lowercased(), kind: .exactName)
}

func spoken(_ id: String, _ name: String, qty: Double?, unit: MeasureUnit?, confident: Bool = true) -> SpokenPantryItem {
    SpokenPantryItem(
        spokenText: name, name: name.lowercased(), qty: qty, unit: unit, match: candidate(id, name),
        isConfident: confident)
}
