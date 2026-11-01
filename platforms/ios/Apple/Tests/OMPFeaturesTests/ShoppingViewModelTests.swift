import Foundation
import OMPDomain
import OMPServices
import Testing

@testable import OMPFeatures

// MARK: Fakes and fixtures

/// A scripted `ShoppingBackend`. Tests run on the main actor one at a time, so the unchecked
/// Sendable conformance is safe here.
private final class FakeShoppingBackend: ShoppingBackend, @unchecked Sendable {
    struct Failure: Error {}

    var list: [ShoppingItem]
    var info: ShoppingPlanInfo
    var failing = false

    private(set) var refreshCalls = 0
    private(set) var added: [String] = []
    private(set) var checkCalls: [(ShoppingItemID, Bool)] = []
    private(set) var removed: [ShoppingItemID] = []
    private(set) var boughtCalls = 0

    init(list: [ShoppingItem], info: ShoppingPlanInfo = approvedInfo) {
        self.list = list
        self.info = info
    }

    func refresh() async throws -> [ShoppingItem] {
        refreshCalls += 1
        if failing { throw Failure() }
        return list
    }

    func items() async throws -> [ShoppingItem] {
        if failing { throw Failure() }
        return list
    }

    func planInfo() async throws -> ShoppingPlanInfo { info }

    func addManual(name: String) async throws {
        if failing { throw Failure() }
        added.append(name)
        list.append(item("manual-\(added.count)", name, origin: .manual))
    }

    func setChecked(_ id: ShoppingItemID, _ checked: Bool) async throws {
        checkCalls.append((id, checked))
        if failing { throw Failure() }
        if let index = list.firstIndex(where: { $0.id == id }) { list[index].checkedOff = checked }
    }

    func remove(_ id: ShoppingItemID) async throws {
        removed.append(id)
        list.removeAll { $0.id == id }
    }

    func boughtEverything() async throws -> Int {
        boughtCalls += 1
        let count = list.filter(\.checkedOff).count
        list.removeAll(where: \.checkedOff)
        return count
    }

    func shareText() async throws -> String {
        "share:" + list.filter { !$0.checkedOff }.map(\.name).joined(separator: ",")
    }
}

private let weekStart = LocalDate(year: 2026, month: 10, day: 12)!
private let approvedInfo = ShoppingPlanInfo(
    approvedRange: weekStart...weekStart.adding(days: 6), hasDraft: false, hasPendingChanges: false)

private func item(
    _ id: String, _ name: String, aisle: Aisle = .other, origin: ShoppingItemOrigin = .plan,
    group: ShoppingItemGroup = .toBuy, quantity: Double? = nil, unit: MeasureUnit? = nil, checked: Bool = false
) -> ShoppingItem {
    ShoppingItem(
        id: ShoppingItemID(id), key: "k:" + id, name: name, quantity: quantity, unit: unit, aisle: aisle,
        checkedOff: checked, origin: origin, group: group)
}

@MainActor
private func loaded(_ backend: FakeShoppingBackend) async -> ShoppingViewModel {
    let model = ShoppingViewModel(backend: backend, clock: FixedClock(now: fixtureNow, timeZone: utc))
    await model.load()
    return model
}

@Suite("ShoppingViewModel")
@MainActor
struct ShoppingViewModelTests {
    @Test("Starts loading, then shows the re-derived list")
    func loads() async {
        let backend = FakeShoppingBackend(list: [item("a", "Onion", aisle: .vegetablesAndFruit)])
        let model = ShoppingViewModel(backend: backend, clock: FixedClock(now: fixtureNow, timeZone: utc))
        #expect(model.phase == .loading)
        await model.load()
        #expect(model.phase == .loaded)
        #expect(model.items.count == 1)
        #expect(backend.refreshCalls == 1)
    }

    @Test("Groups by aisle in aisle order, with Check you have first (AC-10.3, AC-10.4)")
    func sectionOrder() async {
        let backend = FakeShoppingBackend(list: [
            item("a", "Bread", aisle: .bakery),
            item("b", "Onion", aisle: .vegetablesAndFruit),
            item("c", "Milk", aisle: .dairyAndEggs, group: .checkYouHave),
            item("d", "Tomato", aisle: .vegetablesAndFruit),
        ])
        let model = await loaded(backend)
        #expect(model.sections.map(\.kind) == [.checkYouHave, .aisle(.vegetablesAndFruit), .aisle(.bakery)])
        #expect(model.sections[1].items.map(\.name) == ["Onion", "Tomato"])
        #expect(model.sections[0].items.map(\.name) == ["Milk"])
    }

    @Test("No approved plan shows C-140 and still lists manual items (AC-10.2)")
    func noApprovedPlan() async {
        let backend = FakeShoppingBackend(
            list: [item("m", "Masala mix", origin: .notesImport)],
            info: ShoppingPlanInfo(approvedRange: nil, hasDraft: true, hasPendingChanges: false))
        let model = await loaded(backend)
        #expect(model.showsNoPlan)
        #expect(!model.showsNothingToBuy)
        #expect(model.rangeText == nil)
        #expect(model.sections.count == 1)
        #expect(model.originText(model.items[0]) == "from Notes")
    }

    @Test("An approved plan with nothing to buy shows C-141")
    func nothingToBuy() async {
        let model = await loaded(FakeShoppingBackend(list: []))
        #expect(model.showsNothingToBuy)
        #expect(!model.showsNoPlan)
    }

    @Test("A pending plan revision shows the C-142 banner")
    func pendingBanner() async {
        var info = approvedInfo
        info.hasPendingChanges = true
        let model = await loaded(FakeShoppingBackend(list: [item("a", "Onion")], info: info))
        #expect(model.showsPendingChanges)
        let plain = await loaded(FakeShoppingBackend(list: [item("a", "Onion")]))
        #expect(!plain.showsPendingChanges)
    }

    @Test("The range text names the approved week")
    func rangeText() async {
        let model = await loaded(FakeShoppingBackend(list: []))
        let text = model.rangeText ?? ""
        #expect(text.contains("12"))
        #expect(text.contains("18"))
        #expect(text.contains("Oct"))
    }

    @Test("Quantities read naturally: no trailing zeros, pieces without a unit")
    func quantityText() async {
        let model = await loaded(FakeShoppingBackend(list: []))
        #expect(model.quantityText(item("a", "Onion", quantity: 500, unit: .gram)) == "500 g")
        #expect(model.quantityText(item("b", "Milk", quantity: 1.5, unit: .litre)) == "1.5 l")
        #expect(model.quantityText(item("c", "Lemon", quantity: 2, unit: .piece)) == "2")
        #expect(model.quantityText(item("d", "Salt")) == nil)
        #expect(model.lineText(item("e", "Rice", quantity: 1, unit: .kilogram)) == "Rice 1 kg")
        #expect(model.lineText(item("f", "Salt")) == "Salt")
    }

    @Test("Checking an item goes through the service and shows at once (AC-10.5)")
    func check() async {
        let backend = FakeShoppingBackend(list: [item("a", "Onion")])
        let model = await loaded(backend)
        await model.toggle(model.items[0])
        #expect(backend.checkCalls.count == 1)
        #expect(backend.checkCalls[0].1 == true)
        #expect(model.items[0].checkedOff)
        #expect(model.checkedCount == 1)
        await model.toggle(model.items[0])
        #expect(!model.items[0].checkedOff)
    }

    @Test("A failed check-off is reloaded from the service and shows C-095")
    func checkFailure() async {
        let backend = FakeShoppingBackend(list: [item("a", "Onion")])
        let model = await loaded(backend)
        backend.failing = true
        await model.toggle(model.items[0])
        #expect(model.hasError)
    }

    @Test("I have it checks a Check you have line; Need it leaves it unchecked (C-145)")
    func haveItNeedIt() async {
        let backend = FakeShoppingBackend(list: [item("m", "Milk", group: .checkYouHave)])
        let model = await loaded(backend)
        await model.setChecked(model.items[0], true)
        #expect(backend.list[0].checkedOff)
        await model.setChecked(model.items[0], false)
        #expect(!backend.list[0].checkedOff)
    }

    @Test("Adding an item trims the name, adds it via the service and clears the field (AC-10.5)")
    func addManual() async {
        let backend = FakeShoppingBackend(list: [])
        let model = await loaded(backend)
        model.newItemName = "  Paneer  "
        #expect(model.canAdd)
        await model.addItem()
        #expect(backend.added == ["Paneer"])
        #expect(model.newItemName.isEmpty)
        #expect(model.items.count == 1)
    }

    @Test("A blank name is not added")
    func addBlank() async {
        let backend = FakeShoppingBackend(list: [])
        let model = await loaded(backend)
        model.newItemName = "   "
        #expect(!model.canAdd)
        await model.addItem()
        #expect(backend.added.isEmpty)
    }

    @Test("A failed add keeps the typed text and shows C-095")
    func addFailure() async {
        let backend = FakeShoppingBackend(list: [])
        let model = await loaded(backend)
        backend.failing = true
        model.newItemName = "Paneer"
        await model.addItem()
        #expect(model.newItemName == "Paneer")
        #expect(model.hasError)
    }

    @Test("Bought everything is off until something is checked, then asks first (C-143)")
    func boughtNeedsConfirmation() async {
        let backend = FakeShoppingBackend(list: [item("a", "Onion"), item("b", "Rice")])
        let model = await loaded(backend)
        #expect(!model.canBuyEverything)
        model.requestBoughtEverything()
        #expect(!model.isConfirmingBought)

        await model.toggle(model.items[0])
        #expect(model.canBuyEverything)
        model.requestBoughtEverything()
        #expect(model.isConfirmingBought)
        #expect(backend.boughtCalls == 0)

        await model.confirmBoughtEverything()
        #expect(backend.boughtCalls == 1)
        #expect(!model.isConfirmingBought)
        #expect(model.items.count == 1)
        #expect(model.checkedCount == 0)
    }

    @Test("Clear checked items unchecks without deleting")
    func clearChecked() async {
        let backend = FakeShoppingBackend(list: [item("a", "Onion", checked: true), item("b", "Rice", checked: true)])
        let model = await loaded(backend)
        await model.clearChecked()
        #expect(model.items.count == 2)
        #expect(model.checkedCount == 0)
    }

    @Test("Manual and imported items can be removed; plan lines cannot")
    func remove() async {
        let backend = FakeShoppingBackend(list: [item("p", "Onion"), item("m", "Paneer", origin: .manual)])
        let model = await loaded(backend)
        await model.remove(model.items[0])
        #expect(backend.removed.isEmpty)
        await model.remove(model.items[1])
        #expect(backend.removed == [ShoppingItemID("m")])
        #expect(model.items.count == 1)
    }

    @Test("The share text comes from the service and leaves out checked items (AC-10.7)")
    func shareText() async {
        let backend = FakeShoppingBackend(list: [item("a", "Onion"), item("b", "Rice")])
        let model = await loaded(backend)
        #expect(model.shareText == "share:Onion,Rice")
        await model.toggle(model.items[0])
        #expect(model.shareText == "share:Rice")
    }

    @Test("A first load that fails shows the failed phase; Try again recovers")
    func loadFailure() async {
        let backend = FakeShoppingBackend(list: [item("a", "Onion")])
        backend.failing = true
        let model = await loaded(backend)
        #expect(model.phase == .failed)
        backend.failing = false
        await model.retry()
        #expect(model.phase == .loaded)
        #expect(!model.hasError)
    }

    @Test("Without a backend the tab shows the failed phase")
    func noBackend() async {
        let model = ShoppingViewModel(backend: nil, clock: FixedClock(now: fixtureNow, timeZone: utc))
        await model.load()
        #expect(model.phase == .failed)
    }
}
