import Foundation
import OMPDomain
import Testing

@Suite("Shopping list merge and Bought everything (T14: AC-10.2, AC-10.5, AC-10.6)")
struct ShoppingListMergeTests {
    typealias F = ShoppingFixture

    static func derived(
        _ ingredient: IngredientID, _ amount: Double, _ unit: MeasureUnit, group: ShoppingItemGroup = .toBuy
    ) -> DerivedShoppingLine {
        DerivedShoppingLine(
            key: ShoppingDerivation.key(ingredient: ingredient, dimension: unit.dimension, group: group),
            ingredientId: ingredient, name: ingredient.rawValue, quantity: Quantity(amount, unit), aisle: .other,
            group: group)
    }

    static func planItem(
        _ id: ShoppingItemID, _ ingredient: IngredientID, _ amount: Double, _ unit: MeasureUnit, checked: Bool
    ) -> ShoppingItem {
        ShoppingItem(
            id: id, key: ShoppingDerivation.key(ingredient: ingredient, dimension: unit.dimension, group: .toBuy),
            ingredientId: ingredient, name: ingredient.rawValue, quantity: amount, unit: unit, aisle: .other,
            checkedOff: checked, origin: .plan)
    }

    static let manual = ShoppingItem(
        id: "manual-1", key: "manual:bin bags", name: "Bin bags", aisle: .other, checkedOff: true, origin: .manual)
    static let imported = ShoppingItem(
        id: "import-1", key: "import:soap", name: "Soap", quantity: 2, unit: .piece, aisle: .other, origin: .notesImport)

    /// Ids "new-1", "new-2", ... in call order.
    final class Counter {
        var next = 0
        func shoppingId() -> ShoppingItemID {
            next += 1
            return ShoppingItemID("new-\(next)")
        }
        func pantryId() -> PantryItemID {
            next += 1
            return PantryItemID("pantry-new-\(next)")
        }
    }

    @Test("the merge key is plan:<ingredient>:<dimension>:<group>")
    func keyFormat() {
        #expect(ShoppingDerivation.key(ingredient: "ghee", dimension: .volume, group: .toBuy) == "plan:ghee:volume:toBuy")
        #expect(
            ShoppingDerivation.key(ingredient: "milk", dimension: .volume, group: .checkYouHave)
                == "plan:milk:volume:checkYouHave")
    }

    @Test("AC-10.5: a check-off survives re-derivation when the quantity is unchanged")
    func keepsCheckOffOnUnchangedItem() {
        let existing = [Self.planItem("old-1", "rice", 200, .gram, checked: true)]
        let counter = Counter()
        let merged = ShoppingListMerge.merge(
            existing: existing, derived: [Self.derived("rice", 200, .gram)], makeId: counter.shoppingId)
        #expect(merged.count == 1)
        #expect(merged[0].id == "old-1")
        #expect(merged[0].checkedOff)
        #expect(counter.next == 0)
    }

    @Test("AC-10.5: a changed quantity keeps the item id but clears the check-off")
    func clearsCheckOffOnChangedQuantity() {
        let existing = [Self.planItem("old-1", "rice", 200, .gram, checked: true)]
        let merged = ShoppingListMerge.merge(existing: existing, derived: [Self.derived("rice", 400, .gram)])
        #expect(merged.count == 1)
        #expect(merged[0].id == "old-1")
        #expect(merged[0].quantity == 400)
        #expect(!merged[0].checkedOff)
    }

    @Test("AC-10.5: the same amount in another unit counts as changed")
    func clearsCheckOffOnChangedUnit() {
        let existing = [Self.planItem("old-1", "rice", 1, .kilogram, checked: true)]
        let merged = ShoppingListMerge.merge(existing: existing, derived: [Self.derived("rice", 1000, .gram)])
        #expect(!merged[0].checkedOff && merged[0].unit == .gram)
    }

    @Test("AC-10.5: manual and imported items are kept as they are, after the derived lines")
    func keepsManualAndImportedItems() {
        let existing = [Self.manual, Self.planItem("old-1", "rice", 200, .gram, checked: false), Self.imported]
        let counter = Counter()
        let merged = ShoppingListMerge.merge(
            existing: existing, derived: [Self.derived("milk", 40, .millilitre)], makeId: counter.shoppingId)
        #expect(merged.map(\.id) == ["new-1", "manual-1", "import-1"])
        #expect(merged[1] == Self.manual)
        #expect(merged[2] == Self.imported)
        #expect(!merged[0].checkedOff && merged[0].origin == .plan)
        #expect(merged[0].quantity == 40 && merged[0].unit == .millilitre)
    }

    @Test("AC-10.2: with no approved plan only manual and imported items remain")
    func noPlanKeepsOnlyManualAndImported() {
        let draft = PlanFixture.draft(meals: [PlanFixture.meal("meal-1", recipe: "dal-tadka")])
        let existing = [Self.planItem("old-1", "rice", 200, .gram, checked: true), Self.manual, Self.imported]
        let merged = ShoppingListMerge.merge(existing: existing, derived: F.derive(draft))
        #expect(merged == [Self.manual, Self.imported])
    }

    @Test("AC-10.5: re-deriving the same plan is stable (ids and check-offs kept)")
    func rederivationIsStable() throws {
        let plan = try F.dalPlan()
        let counter = Counter()
        var list = ShoppingListMerge.merge(existing: [Self.manual], derived: F.derive(plan), makeId: counter.shoppingId)
        list[0].checkedOff = true
        let again = ShoppingListMerge.merge(existing: list, derived: F.derive(plan), makeId: counter.shoppingId)
        #expect(again == list)
    }

    // MARK: Bought everything (AC-10.6)

    @Test("AC-10.6: checked To buy items go to the pantry and leave the list")
    func boughtEverythingAddsCheckedItems() throws {
        let milk = ShoppingItem(
            id: "s1", key: "plan:milk:volume:toBuy", ingredientId: "milk", name: "Milk", quantity: 500,
            unit: .millilitre, aisle: .dairyAndEggs, checkedOff: true, origin: .plan)
        let rice = ShoppingItem(
            id: "s2", key: "plan:rice:mass:toBuy", ingredientId: "rice", name: "Rice", quantity: 1, unit: .kilogram,
            aisle: .grainsAndFlours, checkedOff: false, origin: .plan)
        let checkYouHave = ShoppingItem(
            id: "s3", key: "plan:ghee:volume:checkYouHave", ingredientId: "ghee", name: "Ghee", quantity: 12,
            unit: .millilitre, aisle: .oilsAndGhee, checkedOff: true, origin: .plan, group: .checkYouHave)
        let counter = Counter()

        let result = ShoppingListMerge.boughtEverything(
            list: [milk, rice, checkYouHave, Self.manual, Self.imported], ingredients: F.ingredients, now: F.now,
            timeZone: F.utc, makeId: counter.pantryId)

        #expect(result.remaining == [rice, Self.imported])
        #expect(result.pantryAdditions.count == 2)
        let addedMilk = result.pantryAdditions[0]
        #expect(addedMilk.item == .ingredient("milk"))
        #expect(addedMilk.quantity == 500 && addedMilk.unit == .millilitre)
        #expect(addedMilk.location == .fridge)
        #expect(addedMilk.expiresOn == F.today.adding(days: 5))
        #expect(addedMilk.purchasedAt == F.now && addedMilk.lastConfirmedAt == F.now)
        #expect(addedMilk.source == .bought)
        #expect(addedMilk.id == "pantry-new-1")

        // A manual free-text item with no amount: 1 piece, unresolved, on the shelf, no expiry.
        let binBags = result.pantryAdditions[1]
        #expect(binBags.item == .freeText("Bin bags"))
        #expect(binBags.quantity == 1 && binBags.unit == .piece)
        #expect(binBags.location == .shelf && binBags.expiresOn == nil)
    }

    @Test("AC-10.6: a bought ingredient with no amount gets 1 of its default unit; shelf items get no expiry")
    func boughtIngredientWithoutAmount() {
        let rice = ShoppingItem(
            id: "s1", key: "manual:rice", ingredientId: "rice", name: "Rice", aisle: .grainsAndFlours, checkedOff: true,
            origin: .manual)
        let result = ShoppingListMerge.boughtEverything(
            list: [rice], ingredients: F.ingredients, now: F.now, timeZone: F.utc)
        #expect(result.pantryAdditions.count == 1)
        #expect(result.pantryAdditions[0].quantity == 1 && result.pantryAdditions[0].unit == .gram)
        #expect(result.pantryAdditions[0].location == .shelf && result.pantryAdditions[0].expiresOn == nil)
        #expect(result.remaining.isEmpty)
    }

    @Test("AC-10.6: bought items are then covered: re-deriving drops them")
    func boughtItemsCoverTheNeed() throws {
        let plan = try F.dalPlan()
        var list = ShoppingListMerge.merge(existing: [], derived: F.derive(plan))
        for index in list.indices { list[index].checkedOff = true }
        let bought = ShoppingListMerge.boughtEverything(list: list, ingredients: F.ingredients, now: F.now, timeZone: F.utc)
        #expect(bought.pantryAdditions.count == 3)
        #expect(F.derive(plan, pantry: bought.pantryAdditions).isEmpty)
    }
}
