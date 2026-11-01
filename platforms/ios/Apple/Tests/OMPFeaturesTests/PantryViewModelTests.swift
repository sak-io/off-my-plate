import Foundation
import OMPDomain
import OMPServices
import Testing

@testable import OMPFeatures

@MainActor
private func makeViewModel(_ backend: FakePantryBackend?) -> PantryViewModel {
    PantryViewModel(backend: backend, clock: FixedClock(now: fixtureNow, timeZone: utc), speech: nil)
}

@Suite("PantryViewModel (S-20)")
@MainActor
struct PantryViewModelTests {
    @Test("AC-9.1: items are grouped by place (fridge, freezer, shelf) and sorted by name")
    func groupsByLocation() async {
        let backend = FakePantryBackend(stored: [
            pantryItem("a", "rice", 2, .kilogram, .shelf),
            pantryItem("b", "milk", 1, .litre, .fridge),
            pantryItem("c", "egg", 12, .piece, .fridge),
        ])
        let model = makeViewModel(backend)
        await model.load()
        #expect(model.phase == .loaded)
        #expect(model.groups.map(\.location) == [.fridge, .shelf])
        #expect(model.groups[0].rows.map(\.name) == ["Egg", "Milk"])
        #expect(model.groups[1].rows.map(\.name) == ["Rice"])
        #expect(model.groups[1].rows[0].amountText == "2 kg")
    }

    @Test("An empty pantry shows the empty state, not a list")
    func emptyPantry() async {
        let model = makeViewModel(FakePantryBackend())
        await model.load()
        #expect(model.phase == .loaded)
        #expect(model.isEmpty)
        #expect(model.groups.isEmpty)
        #expect(!model.hasNoSearchResults)
    }

    @Test("AC-9.7: a fridge item is stale after 7 days, a shelf item after 60; the check is calendar days")
    func staleItems() async {
        let backend = FakePantryBackend(stored: [
            pantryItem("fresh", "milk", 1, .litre, .fridge, confirmedDaysAgo: 7),
            pantryItem("stale", "egg", 6, .piece, .fridge, confirmedDaysAgo: 8),
            pantryItem("shelf-ok", "rice", 1, .kilogram, .shelf, confirmedDaysAgo: 60),
            pantryItem("shelf-stale", "onion", 3, .piece, .shelf, confirmedDaysAgo: 61),
        ])
        let model = makeViewModel(backend)
        await model.load()
        let rows = model.groups.flatMap(\.rows)
        func stale(_ id: String) -> Bool { rows.first { $0.id == PantryItemID(id) }?.isStale ?? false }
        #expect(!stale("fresh"))
        #expect(stale("stale"))
        #expect(!stale("shelf-ok"))
        #expect(stale("shelf-stale"))
    }

    @Test("AC-9.2: a free-text item is flagged unresolved; a matched one is not")
    func unresolvedItems() async {
        let backend = FakePantryBackend(stored: [
            freeTextItem("x", "masala mix"), pantryItem("r", "rice", 1, .kilogram, .shelf),
        ])
        let model = makeViewModel(backend)
        await model.load()
        let rows = model.groups.flatMap(\.rows)
        #expect(rows.first { $0.id == "x" }?.isUnresolved == true)
        #expect(rows.first { $0.id == "x" }?.name == "masala mix")
        #expect(rows.first { $0.id == "r" }?.isUnresolved == false)
    }

    @Test("Search keeps matching rows; no match gives the C-124 text with the query")
    func search() async {
        let backend = FakePantryBackend(stored: [
            pantryItem("a", "rice", 2, .kilogram, .shelf), pantryItem("b", "milk", 1, .litre, .fridge),
        ])
        let model = makeViewModel(backend)
        await model.load()
        model.searchText = "ric"
        #expect(model.groups.flatMap(\.rows).map(\.name) == ["Rice"])
        #expect(!model.hasNoSearchResults)
        model.searchText = "  zzz "
        #expect(model.groups.isEmpty)
        #expect(model.hasNoSearchResults)
        #expect(model.noResultsText == PantryCopy.noResults("zzz"))
        model.searchText = ""
        #expect(model.groups.count == 2)
    }

    @Test("AC-9.7: Still have it goes through the service and clears the stale flag")
    func stillHaveIt() async {
        let backend = FakePantryBackend(stored: [pantryItem("m", "milk", 1, .litre, .fridge, confirmedDaysAgo: 10)])
        let model = makeViewModel(backend)
        await model.load()
        #expect(model.groups[0].rows[0].isStale)
        await model.reconfirm("m")
        #expect(backend.reconfirmed == ["m"])
        #expect(!model.groups[0].rows[0].isStale)
        #expect(model.errorMessage == nil)
    }

    @Test("Delete goes through the service and removes the row")
    func delete() async {
        let backend = FakePantryBackend(stored: [pantryItem("a", "rice", 2, .kilogram, .shelf)])
        let model = makeViewModel(backend)
        await model.load()
        await model.delete("a")
        #expect(backend.deleted == ["a"])
        #expect(model.isEmpty)
    }

    @Test("A failed change shows C-095 and keeps the list as the service has it")
    func failedChange() async {
        let backend = FakePantryBackend(stored: [pantryItem("a", "rice", 2, .kilogram, .shelf)])
        let model = makeViewModel(backend)
        await model.load()
        backend.failure = PantryFixtureError.boom
        await model.delete("a")
        #expect(model.errorMessage == PantryCopy.saveFailed)
        #expect(model.items.count == 1)
        backend.failure = nil
        await model.sheetChangedPantry()
        #expect(model.errorMessage == nil)
    }

    @Test("A load that fails shows the error phase; retry recovers")
    func loadFails() async {
        let backend = FakePantryBackend(stored: [pantryItem("a", "rice", 2, .kilogram, .shelf)])
        backend.failure = PantryFixtureError.boom
        let model = makeViewModel(backend)
        await model.load()
        #expect(model.phase == .failed)
        #expect(model.errorMessage == PantryCopy.loadFailed)
        backend.failure = nil
        await model.retry()
        #expect(model.phase == .loaded)
        #expect(model.errorMessage == nil)
    }

    @Test("Without services the pantry reports the error instead of an empty list")
    func noBackend() async {
        let model = makeViewModel(nil)
        await model.load()
        #expect(model.phase == .failed)
    }

    @Test("Use-by text: within a week the weekday, later the date, earlier 'Past use-by date'")
    func useBy() async {
        let today = LocalDate(year: 2026, month: 10, day: 12)!
        let backend = FakePantryBackend(stored: [
            pantryItem("soon", "milk", 1, .litre, .fridge, expiresOn: today.adding(days: 3)),
            pantryItem("later", "egg", 6, .piece, .fridge, expiresOn: today.adding(days: 13)),
            pantryItem("over", "onion", 3, .piece, .shelf, expiresOn: today.adding(days: -2)),
            pantryItem("none", "rice", 1, .kilogram, .shelf),
        ])
        let model = makeViewModel(backend)
        await model.load()
        let rows = model.groups.flatMap(\.rows)
        func text(_ id: String) -> String? { rows.first { $0.id == PantryItemID(id) }?.useByText }
        #expect(text("soon") == PantryCopy.useByWeekday(PantryFormat.weekdayName(today.adding(days: 3), in: utc)))
        #expect(text("later") == PantryCopy.useByDate(PantryFormat.shortDate(today.adding(days: 13), in: utc)))
        #expect(text("over") == PantryCopy.pastUseBy)
        #expect(text("none") == nil)
    }

    @Test("The mic opens the speak sheet; Type instead swaps sheets only after the first is gone")
    func sheets() async {
        let backend = FakePantryBackend(stored: [pantryItem("a", "rice", 2, .kilogram, .shelf)])
        let model = makeViewModel(backend)
        await model.load()
        model.openSpeak()
        #expect(model.sheet == .speak)
        model.replaceSheet(with: .add(nil))
        #expect(model.sheet == nil)
        #expect(model.pendingSheet == .add(nil))
        model.sheetDismissed()
        #expect(model.sheet == .add(nil))
        #expect(model.pendingSheet == nil)
        model.sheet = nil
        model.sheetDismissed()
        #expect(model.sheet == nil)
        model.openEdit("a")
        #expect(model.sheet == .edit("a"))
        model.sheet = nil
        model.openEdit("missing")
        #expect(model.sheet == nil)
    }
}
