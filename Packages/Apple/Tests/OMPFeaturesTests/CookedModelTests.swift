import Foundation
import OMPDomain
import OMPServices
import Testing

@testable import OMPFeatures

private func line(_ id: String, _ name: String, need: Double, _ unit: MeasureUnit, have: Double?) -> CookLine {
    CookLine(
        ingredientId: IngredientID(id), name: name, proposed: Quantity(need, unit),
        have: have.map { Quantity($0, unit) })
}

private func rajmaProposal() -> CookProposal {
    CookProposal(
        mealTitle: "Rajma chawal",
        lines: [
            line("rajma", "Rajma", need: 220, .gram, have: 500),
            line("rice", "Rice", need: 300, .gram, have: 2000),
            line("onion", "Onion", need: 2, .piece, have: 1),
            line("ginger", "Ginger", need: 10, .gram, have: nil),
        ])
}

@MainActor
private func makeModel(_ backend: FakePantryBackend?) -> CookedModel {
    CookedModel(backend: backend, plan: "plan-1", meal: "meal-1")
}

@Suite("CookedModel (S-15)")
@MainActor
struct CookedModelTests {
    @Test("AC-9.6: the sheet proposes the recipe amounts against what the pantry holds")
    func proposal() async {
        let backend = FakePantryBackend()
        backend.proposal = rajmaProposal()
        let model = makeModel(backend)
        await model.load()
        #expect(model.phase == .ready)
        #expect(model.mealTitle == "Rajma chawal")
        #expect(model.lines.map(\.name) == ["Rajma", "Rice", "Onion", "Ginger"])
        #expect(model.lines[0].amount == 220)
        #expect(model.lines[0].have == 500)
        #expect(!model.lines[0].willBeZero)
    }

    @Test("Never below zero: using more than is there shows 'Will be 0'; ginger is not in the pantry")
    func willBeZero() async {
        let backend = FakePantryBackend()
        backend.proposal = rajmaProposal()
        let model = makeModel(backend)
        await model.load()
        #expect(model.lines[2].willBeZero)
        #expect(model.lines[3].have == nil)
        #expect(!model.lines[3].willBeZero)
        model.toggleEditing("ginger")
        #expect(!model.lines[3].isEditing)
    }

    @Test("AC-9.6: editing an amount changes what is taken out of the pantry")
    func editChangesDeduction() async {
        let backend = FakePantryBackend()
        backend.proposal = rajmaProposal()
        let model = makeModel(backend)
        await model.load()
        model.toggleEditing("rajma")
        #expect(model.lines[0].isEditing)
        model.decrease("rajma")
        #expect(model.lines[0].amount == 210)
        model.increase("rice")
        model.increase("rice")
        #expect(model.lines[1].amount == 320)
        model.setAmount("onion", text: "1")
        #expect(model.lines[2].willBeZero)
        model.setAmount("onion", text: "bogus")
        #expect(model.lines[2].amount == 1)
        await model.update()
        let amounts = backend.cookedAmounts.first ?? []
        #expect(amounts.count == 4)
        #expect(amounts.first { $0.ingredientId == "rajma" }?.quantity == Quantity(210, .gram))
        #expect(amounts.first { $0.ingredientId == "rice" }?.quantity == Quantity(320, .gram))
        #expect(amounts.first { $0.ingredientId == "onion" }?.quantity == Quantity(1, .piece))
        #expect(model.didFinish)
    }

    @Test("Minus stops at zero and plus uses the unit's step")
    func steps() async {
        let backend = FakePantryBackend()
        backend.proposal = CookProposal(
            mealTitle: "Kheer", lines: [line("milk", "Milk", need: 0.5, .litre, have: 2)])
        let model = makeModel(backend)
        await model.load()
        model.decrease("milk")
        #expect(model.lines[0].amount == 0)
        model.decrease("milk")
        #expect(model.lines[0].amount == 0)
        model.increase("milk")
        #expect(model.lines[0].amount == 0.5)
    }

    @Test("AC-5.3, AC-9.6: a plan that is not approved is refused with the C-066 text and nothing is cooked")
    func notApproved() async {
        let backend = FakePantryBackend()
        backend.cookFailure = ServiceError.markCooked(.planNotApproved)
        let model = makeModel(backend)
        await model.load()
        #expect(model.phase == .failed(PantryCopy.notApproved))
        #expect(!model.canUpdate)
        await model.update()
        #expect(backend.cookedAmounts.isEmpty)
        #expect(!model.didFinish)
    }

    @Test("A meal already cooked is refused")
    func alreadyCooked() async {
        let backend = FakePantryBackend()
        backend.cookFailure = ServiceError.markCooked(.alreadyCooked("meal-1"))
        let model = makeModel(backend)
        await model.load()
        #expect(model.phase == .failed(PantryCopy.alreadyCooked))
    }

    @Test("A failing update shows the error and keeps the sheet open")
    func updateFails() async {
        let backend = FakePantryBackend()
        backend.proposal = rajmaProposal()
        let model = makeModel(backend)
        await model.load()
        backend.cookFailure = PantryFixtureError.boom
        await model.update()
        #expect(model.errorMessage == PantryCopy.saveFailed)
        #expect(!model.didFinish)
        #expect(!model.isSaving)
        backend.cookFailure = nil
        await model.update()
        #expect(model.didFinish)
        #expect(model.errorMessage == nil)
    }

    @Test("Without services the sheet reports an error")
    func noBackend() async {
        let model = makeModel(nil)
        await model.load()
        #expect(model.phase == .failed(PantryCopy.saveFailed))
    }

    @Test("Using more than the pantry holds is passed on as edited (the service stops at zero); a second update is refused")
    func usedMoreThanHave() async {
        let backend = FakePantryBackend()
        backend.proposal = rajmaProposal()
        let model = makeModel(backend)
        await model.load()
        model.setAmount("onion", text: "5")
        #expect(model.lines[2].amount == 5)
        #expect(model.lines[2].willBeZero)
        await model.update()
        #expect(backend.cookedAmounts.first?.first { $0.ingredientId == "onion" }?.quantity == Quantity(5, .piece))
        #expect(!model.canUpdate)
        await model.update()
        #expect(backend.cookedAmounts.count == 1)
    }
}
