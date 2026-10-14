import Foundation
import OMPDomain
@testable import OMPServices
import Testing

@Suite("ShoppingService: derive/merge, manual items, Bought everything, share text (AC-10.x, T19)")
struct ShoppingServiceTests {
    @Test("with no approved plan the list holds only manual items (AC-10.2)")
    func noPlanOnlyManual() async throws {
        let env = ServicesBEnv()
        try await env.base.onboardWithoutRules()
        _ = try await env.base.plans.generateWeek()  // a draft: still no list
        let manual = try await env.shopping.addManual(ShoppingItemInput(name: "Bin bags"))
        let list = try await env.shopping.refresh()
        #expect(list == [manual])
        #expect(manual.origin == .manual)
        #expect(manual.ingredientId == nil)
        #expect(manual.aisle == .other)
    }

    @Test("an approved plan derives plan lines; manual items and check-offs survive re-derivation (AC-10.1, AC-10.5)")
    func derivesAndKeepsManualAndCheckOffs() async throws {
        let env = ServicesBEnv()
        _ = try await env.base.approvedWeek()
        let manual = try await env.shopping.addManual(
            ShoppingItemInput(name: "rice", quantity: 2, unit: .kilogram))
        #expect(manual.ingredientId == ServicesBFixture.rice)
        #expect(manual.aisle == .grainsAndFlours)
        #expect(manual.quantity == 2)

        let list = try await env.shopping.refresh()
        let plan = list.filter { $0.origin == .plan }
        try #require(!plan.isEmpty)
        #expect(list.contains(manual))

        let first = try #require(plan.first)
        try await env.shopping.setChecked(first.id, true)
        let again = try await env.shopping.refresh()
        #expect(again.first { $0.id == first.id }?.checkedOff == true)
        #expect(again.contains(manual))
        #expect(again.filter { $0.origin == .plan }.count == plan.count)
    }

    @Test("a manual item can be removed; a plan line cannot (AC-10.5)")
    func removal() async throws {
        let env = ServicesBEnv()
        _ = try await env.base.approvedWeek()
        let manual = try await env.shopping.addManual(ShoppingItemInput(name: "Salt"))
        let planLine = try #require(try await env.shopping.refresh().first { $0.origin == .plan })
        let refused = await serviceError { try await env.shopping.remove(planLine.id) }
        guard case .invalidInput? = refused else {
            Issue.record("expected invalidInput, got \(String(describing: refused))")
            return
        }
        try await env.shopping.remove(manual.id)
        let remaining = try await env.shopping.items()
        #expect(!remaining.contains(manual))
        let missing = await serviceError { try await env.shopping.setChecked("nope", true) }
        #expect(missing == .shoppingItemNotFound("nope"))
    }

    @Test("Bought everything moves checked to-buy items into the pantry as bought and clears them (AC-10.6)")
    func boughtEverything() async throws {
        let env = ServicesBEnv()
        _ = try await env.base.approvedWeek()
        let list = try await env.shopping.refresh()
        let toBuy = list.filter { $0.origin == .plan && $0.group == .toBuy }
        try #require(toBuy.count >= 2)
        let chosen = Array(toBuy.prefix(2))
        for item in chosen { try await env.shopping.setChecked(item.id, true) }
        let manual = try await env.shopping.addManual(ShoppingItemInput(name: "Salt"))
        try await env.shopping.setChecked(manual.id, true)

        let added = try await env.shopping.boughtEverything()
        // Two plan lines and the checked manual item each become one pantry item.
        #expect(added.count == 3)
        #expect(added.allSatisfy { $0.source == .bought && $0.lastConfirmedAt == ServicesFixture.now })
        #expect(try await env.pantry.items().count == 3)

        let after = try await env.shopping.items()
        #expect(!after.contains { $0.checkedOff })
        // The pantry now covers those plan needs, so they stay off the list.
        for item in chosen {
            let id = try #require(item.ingredientId)
            let stillThere = after.contains { $0.ingredientId == id && $0.origin == .plan && $0.group == .toBuy }
            #expect(!stillThere)
        }
    }

    @Test("a checked \"Check you have\" item confirms the pantry instead of adding stock (AC-10.4, handoff Q2)")
    func checkYouHaveConfirmsPantry() async throws {
        let env = ServicesBEnv()
        _ = try await env.base.approvedWeek()
        // A lot of rice, last confirmed long ago: it covers the need but is only low confidence.
        let stale = PantryItem(
            id: "old-rice", item: .ingredient(ServicesBFixture.rice), quantity: 100, unit: .kilogram,
            location: .fridge, lastConfirmedAt: ServicesFixture.now.addingTimeInterval(-30 * 86_400),
            source: .manual)
        try await env.repositories.pantry.save(stale)

        let list = try await env.shopping.refresh()
        let check = try #require(
            list.first { $0.ingredientId == ServicesBFixture.rice && $0.group == .checkYouHave })
        try await env.shopping.setChecked(check.id, true)

        let added = try await env.shopping.boughtEverything()
        #expect(added.isEmpty)
        let confirmed = try #require(try await env.repositories.pantry.fetch(id: "old-rice"))
        #expect(confirmed.lastConfirmedAt == ServicesFixture.now)
        let after = try await env.shopping.items()
        #expect(!after.contains { $0.ingredientId == ServicesBFixture.rice })
    }

    // MARK: Share text (AC-10.7)

    @Test("share text format (golden)")
    func shareTextGolden() throws {
        func item(
            _ id: String, _ name: String, _ quantity: Double?, _ unit: MeasureUnit?, _ aisle: Aisle,
            group: ShoppingItemGroup = .toBuy, checked: Bool = false
        ) -> ShoppingItem {
            ShoppingItem(
                id: ShoppingItemID(id), key: id, name: name, quantity: quantity, unit: unit, aisle: aisle,
                checkedOff: checked, origin: .plan, group: group)
        }
        let items = [
            item("1", "Eggs", 12, .piece, .dairyAndEggs),
            item("2", "Spinach", 500, .gram, .vegetablesAndFruit),
            item("3", "Curd", 1.5, .litre, .dairyAndEggs),
            item("4", "Bin bags", nil, nil, .other),
            item("5", "Rice", 0.25, .kilogram, .grainsAndFlours, group: .checkYouHave),
            item("6", "Salt", 1, .kilogram, .other, checked: true),
        ]
        let first = try #require(LocalDate(year: 2026, month: 10, day: 12))
        let last = try #require(LocalDate(year: 2026, month: 10, day: 18))
        let text = ShoppingShareText.render(items: items, range: first...last)
        #expect(
            text == """
                Shopping list for 2026-10-12 to 2026-10-18 (from OffMyPlate)

                Vegetables & fruit
                - Spinach 500 g

                Dairy & eggs
                - Eggs 12
                - Curd 1.5 l

                Other
                - Bin bags

                Check you have
                - Rice 0.25 kg

                """)
        #expect(ShoppingShareText.render(items: [], range: nil) == "Shopping list (from OffMyPlate)\n")
    }

    @Test("share text amounts are rounded for display only")
    func shareAmounts() {
        #expect(ShoppingShareText.amount(0.1 + 0.2) == "0.3")
        #expect(ShoppingShareText.amount(2.0) == "2")
        #expect(ShoppingShareText.amount(0.05) == "0.05")
        #expect(ShoppingShareText.amount(.nan) == "0")
    }

    @Test("the service shares the approved plan's list under its date range")
    func shareFromService() async throws {
        let env = ServicesBEnv()
        let approved = try await env.base.approvedWeek()
        try await env.shopping.addManual(ShoppingItemInput(name: "Bin bags"))
        try await env.shopping.refresh()
        let text = try await env.shopping.shareText()
        let header = "Shopping list for \(approved.weekStart.isoString) to \(approved.endDate.isoString) (from OffMyPlate)\n"
        #expect(text.hasPrefix(header))
        #expect(text.contains("\nOther\n- Bin bags\n"))
    }
}
