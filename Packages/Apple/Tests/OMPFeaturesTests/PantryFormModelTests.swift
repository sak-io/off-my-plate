import Foundation
import OMPDomain
import OMPServices
import Testing

@testable import OMPFeatures

@MainActor
private func makeForm(
    _ backend: FakePantryBackend, item: PantryItem? = nil, name: String = "", prefill: PantryFormPrefill? = nil
) -> PantryFormModel {
    PantryFormModel(
        backend: backend, clock: FixedClock(now: fixtureNow, timeZone: utc), item: item, displayName: name,
        prefill: prefill)
}

@Suite("PantryFormModel (S-21)")
@MainActor
struct PantryFormModelTests {
    @Test("Save is off until a name and a positive amount are present")
    func saveNeedsNameAndAmount() {
        let form = makeForm(FakePantryBackend())
        #expect(!form.canSave)
        form.typeName("Rice")
        #expect(!form.canSave)
        form.amountText = "0"
        #expect(!form.canSave)
        form.amountText = "abc"
        #expect(!form.canSave)
        form.amountText = "2,5"
        #expect(form.canSave)
        #expect(form.amount == 2.5)
        form.typeName("   ")
        #expect(!form.canSave)
    }

    @Test("Typing offers suggestions; picking one fills the name, ingredient, unit and place")
    func pickSuggestion() {
        let form = makeForm(FakePantryBackend())
        form.typeName("mil")
        #expect(form.suggestions.map(\.name) == ["Milk"])
        #expect(form.offersAddAsTyped)
        form.pick(form.suggestions[0])
        #expect(form.name == "Milk")
        #expect(form.ingredientId == "milk")
        #expect(form.unit == .litre)
        #expect(form.location == .fridge)
        #expect(form.suggestions.isEmpty)
        #expect(!form.offersAddAsTyped)
        form.typeName("Milky")
        #expect(form.ingredientId == nil)
    }

    @Test("AC-9.2: adding 'as typed' keeps free text; the note offer disappears")
    func addAsTyped() async {
        let backend = FakePantryBackend()
        let form = makeForm(backend)
        form.typeName("masala mix")
        #expect(form.offersAddAsTyped)
        form.keepAsTyped()
        #expect(!form.offersAddAsTyped)
        form.amountText = "1"
        form.unit = .piece
        #expect(await form.save())
        #expect(backend.added.count == 1)
        #expect(backend.added[0].name == "masala mix")
        #expect(backend.added[0].ingredientId == nil)
    }

    @Test("AC-9.1: saving a new item sends name, ingredient, amount, unit, place and use-by to the service")
    func addSendsInput() async {
        let backend = FakePantryBackend()
        let form = makeForm(backend)
        form.typeName("ric")
        form.pick(form.suggestions[0])
        form.amountText = "1.5"
        form.unit = .kilogram
        form.location = .shelf
        form.hasUseBy = true
        #expect(await form.save())
        let input = backend.added[0]
        #expect(input.name == "Rice")
        #expect(input.ingredientId == "rice")
        #expect(input.quantity == 1.5)
        #expect(input.unit == .kilogram)
        #expect(input.location == .shelf)
        #expect(input.expiresOn == LocalDate(year: 2026, month: 10, day: 19))
    }

    @Test("Without a use-by date the item has none")
    func noUseBy() async {
        let backend = FakePantryBackend()
        let form = makeForm(backend)
        form.typeName("Onion")
        form.amountText = "3"
        #expect(await form.save())
        #expect(backend.added[0].expiresOn == nil)
    }

    @Test("Edit starts from the item and saves through update, keeping the picked ingredient")
    func editItem() async {
        let item = pantryItem(
            "a", "rice", 2, .kilogram, .shelf, expiresOn: LocalDate(year: 2026, month: 11, day: 1))
        let backend = FakePantryBackend(stored: [item])
        let form = makeForm(backend, item: item, name: "Rice")
        #expect(form.isEditing)
        #expect(form.name == "Rice")
        #expect(form.amountText == "2")
        #expect(form.unit == .kilogram)
        #expect(form.hasUseBy)
        #expect(form.ingredientId == "rice")
        #expect(form.suggestions.isEmpty)
        form.amountText = "1.25"
        #expect(await form.save())
        #expect(backend.updated.count == 1)
        #expect(backend.updated[0].0 == "a")
        #expect(backend.updated[0].1.quantity == 1.25)
        #expect(backend.updated[0].1.ingredientId == "rice")
        #expect(backend.updated[0].1.expiresOn == LocalDate(year: 2026, month: 11, day: 1))
        #expect(backend.added.isEmpty)
    }

    @Test("AC-9.2: Match it on a free-text item shows suggestions and saves the matched ingredient")
    func matchFreeText() async {
        let item = freeTextItem("x", "rice")
        let backend = FakePantryBackend(stored: [item])
        let form = makeForm(backend, item: item, name: "rice")
        #expect(form.ingredientId == nil)
        #expect(form.suggestions.map(\.name) == ["Rice"])
        form.pick(form.suggestions[0])
        #expect(await form.save())
        #expect(backend.updated[0].1.ingredientId == "rice")
        #expect(backend.stored[0].item == .ingredient("rice"))
    }

    @Test("Delete is only for an edited item and goes through the service")
    func deleteItem() async {
        let item = pantryItem("a", "rice", 2, .kilogram, .shelf)
        let backend = FakePantryBackend(stored: [item])
        let adding = makeForm(backend)
        #expect(!(await adding.delete()))
        let form = makeForm(backend, item: item, name: "Rice")
        #expect(await form.delete())
        #expect(backend.deleted == ["a"])
    }

    @Test("A failed save shows C-095 and does not close")
    func failedSave() async {
        let backend = FakePantryBackend()
        backend.failure = PantryFixtureError.boom
        let form = makeForm(backend)
        form.typeName("Rice")
        form.amountText = "1"
        #expect(!(await form.save()))
        #expect(form.errorMessage == PantryCopy.saveFailed)
        #expect(!form.isSaving)
    }

    @Test("A voice leftover prefills the name and shows what was said (C-133)")
    func prefillFromVoice() {
        let form = makeForm(
            FakePantryBackend(), prefill: PantryFormPrefill(name: "some of that stuff", transcript: "I bought some of that stuff"))
        #expect(form.name == "some of that stuff")
        #expect(form.transcript == "I bought some of that stuff")
        #expect(!form.canSave)
    }

    @Test("Amount formatting rounds at display only; parsing accepts a dot or a comma")
    func formatting() {
        #expect(PantryFormat.number(220) == "220")
        #expect(PantryFormat.number(2.5) == "2.5")
        #expect(PantryFormat.number(0.3333333) == "0.33")
        #expect(PantryFormat.number(1500) == "1500")
        #expect(PantryFormat.amount(220, .gram) == "220 g")
        #expect(PantryFormat.amount(12, .piece) == "12 pcs")
        #expect(PantryFormat.parseAmount(" 1,5 ") == 1.5)
        #expect(PantryFormat.parseAmount("-1") == nil)
        #expect(PantryFormat.parseAmount("") == nil)
        #expect(PantryFormat.parseAmount("1e12") == nil)
        #expect(PantryFormat.parseAmount("nan") == nil)
        #expect(PantryFormat.units(including: .tablespoon).last == .tablespoon)
        #expect(PantryFormat.units(including: .gram) == PantryFormat.formUnits)
    }
}
