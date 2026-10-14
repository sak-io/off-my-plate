import Foundation
import OMPDomain

/// What one `drainInbox()` did (copy C-111: "Added {n} items from Notes.").
public struct ImportSummary: Sendable, Hashable {
    /// New shopping or pantry rows created.
    public var itemsAdded = 0
    /// Items folded into an existing row (same ingredient, or same text).
    public var itemsMerged = 0
    /// Where the imported items went.
    public var destinations: Set<InboxImport.Destination> = []
    /// Files merged by this drain.
    public var filesImported = 0
    /// Files whose id was already merged earlier (a leftover file); removed without merging.
    public var alreadyImported = 0
    /// Names of the files moved to `failed/` because they could not be read (ADR 0011). The app
    /// tells the user; nothing is dropped silently.
    public var quarantined: [String] = []
    /// Names of unreadable files that could not even be moved; they are tried again next time.
    public var stuck: [String] = []

    public init() {}

    /// The number the toast shows.
    public var itemsTotal: Int { itemsAdded + itemsMerged }
}

/// Merges the Share Extension's inbox files into the list or pantry (AC-11.3, AC-11.5, ADR 0011;
/// task T19).
///
/// - **Idempotent.** A file is merged once: its id is recorded in the `ProcessedImportStore`
///   before the file is deleted, so a second drain, or a file that could not be deleted, never
///   merges twice. (If the app stops between merging and recording, the next drain merges the
///   file again; a visible duplicate is preferred to silently losing the user's items.)
/// - **Corrupt files are quarantined**, not dropped.
/// - **Learning evidence only.** Each resolved item adds one `.importedItem` event (a staple
///   signal). Imports never read or write rules, members or safety status (AC-11.5).
/// - Items are de-duplicated against existing non-plan rows by ingredient (or by name for free
///   text). Plan-derived shopping lines are never edited: they are recomputed from the plan.
public final class ImportService: Sendable {
    let context: ServiceContext
    let inbox: any InboxStorage
    let processed: any ProcessedImportStore

    public init(context: ServiceContext, inbox: any InboxStorage, processedImports: any ProcessedImportStore) {
        self.context = context
        self.inbox = inbox
        self.processed = processedImports
    }

    /// Drains the inbox (the app calls this when the scene becomes active).
    @discardableResult
    public func drainInbox() async throws -> ImportSummary {
        try await context.serialized {
            var summary = ImportSummary()
            let now = context.clock.now
            let names = InboxFiles.inboxFileNames(in: try await inbox.fileNames())
            for name in names {
                guard let id = InboxFiles.importID(fromFileName: name) else { continue }
                if try await processed.contains(id) {
                    try? await inbox.remove(name)
                    summary.alreadyImported += 1
                    continue
                }
                let parsed: InboxImport
                do {
                    let data = try await inbox.read(name)
                    parsed = try InboxImport.decode(data)
                    guard parsed.importId == id else {
                        throw InboxImportError.invalid("The import id does not match the file name.")
                    }
                } catch {
                    do {
                        try await inbox.quarantine(name)
                        summary.quarantined.append(name)
                    } catch {
                        summary.stuck.append(name)
                    }
                    continue
                }
                switch parsed.destination {
                case .shoppingList: try await mergeIntoShoppingList(parsed.items, now: now, into: &summary)
                case .pantry: try await mergeIntoPantry(parsed.items, now: now, into: &summary)
                }
                try await logStaples(parsed.items, now: now)
                try await processed.insert(id, at: now)
                try? await inbox.remove(name)
                summary.destinations.insert(parsed.destination)
                summary.filesImported += 1
            }
            if summary.filesImported > 0 {
                try await ShoppingEngine(context: context).rederive()
            }
            return summary
        }
    }

    // MARK: Private

    /// The taxonomy ingredient for an item: the one the review row carried (if it is in the
    /// library), else a confident match of the name.
    private func ingredient(for item: InboxImport.Item) -> Ingredient? {
        if let id = item.ingredientId, let known = context.library.ingredientsByID[id] { return known }
        guard let match = context.library.resolver.confidentMatch(for: item.name) else { return nil }
        return context.library.ingredientsByID[match.ingredientId]
    }

    /// The imported amount, if the row had one (unit defaults to the ingredient's, else pieces).
    private func quantity(of item: InboxImport.Item, ingredient: Ingredient?) -> Quantity? {
        guard let amount = item.quantity else { return nil }
        let unit = item.unit ?? ingredient?.defaultUnit ?? .piece
        let result = Quantity(amount, unit)
        return result.isQuantified && !result.isZero ? result : nil
    }

    private func mergeIntoShoppingList(
        _ items: [InboxImport.Item], now: Date, into summary: inout ImportSummary
    ) async throws {
        let repository = context.repositories.shopping
        var list = try await repository.fetchAll()
        for item in items {
            let found = ingredient(for: item)
            let incoming = quantity(of: item, ingredient: found)
            let normalised = IngredientResolver.normalise(item.name)
            let index = list.firstIndex { existing in
                guard existing.origin != .plan, !existing.checkedOff else { return false }
                if let found { return existing.ingredientId == found.id }
                return existing.ingredientId == nil && IngredientResolver.normalise(existing.name) == normalised
            }
            if let index {
                var existing = list[index]
                if let incoming, let have = existing.quantity, let unit = existing.unit {
                    let profile = found.map(ConversionProfile.init(ingredient:)) ?? .sameDimensionOnly
                    if let sum = Quantity(have, unit).adding(incoming, using: profile) {
                        existing.quantity = sum.amount
                        existing.unit = sum.unit
                    }
                }
                if existing != list[index] {
                    list[index] = existing
                    try await repository.save(existing)
                }
                summary.itemsMerged += 1
            } else {
                let created = ShoppingItem(
                    id: ShoppingItemID(context.makeID()),
                    key: "import:" + (found?.id.rawValue ?? "text:" + normalised),
                    ingredientId: found?.id, name: found?.name ?? item.name,
                    quantity: incoming?.amount, unit: incoming?.unit, aisle: found?.aisle ?? .other,
                    origin: .notesImport)
                list.append(created)
                try await repository.save(created)
                summary.itemsAdded += 1
            }
        }
    }

    private func mergeIntoPantry(
        _ items: [InboxImport.Item], now: Date, into summary: inout ImportSummary
    ) async throws {
        let repository = context.repositories.pantry
        let engine = ShoppingEngine(context: context)
        var pantry = try await repository.fetchAll()
        for item in items {
            let found = ingredient(for: item)
            let incoming = quantity(of: item, ingredient: found)
            let normalised = IngredientResolver.normalise(item.name)
            let index = pantry.firstIndex { existing in
                if let found { return existing.item.ingredientId == found.id }
                if case .freeText(let text) = existing.item { return IngredientResolver.normalise(text) == normalised }
                return false
            }
            if let index {
                var existing = pantry[index]
                if let incoming {
                    let profile = found.map(ConversionProfile.init(ingredient:)) ?? .sameDimensionOnly
                    if let sum = existing.amount.adding(incoming, using: profile) {
                        existing.quantity = sum.amount
                    }
                }
                existing.lastConfirmedAt = now
                pantry[index] = existing
                try await repository.save(existing)
                summary.itemsMerged += 1
            } else {
                let location = found?.defaultLocation ?? .shelf
                let amount = incoming ?? Quantity(1, found?.defaultUnit ?? .piece)
                let reference: PantryItemRef = found.map { .ingredient($0.id) } ?? .freeText(item.name)
                let created = PantryItem(
                    id: PantryItemID(context.makeID()), item: reference, quantity: amount.amount, unit: amount.unit,
                    location: location, purchasedAt: now, expiresOn: engine.expiry(for: found, location: location, now: now),
                    lastConfirmedAt: now, source: .notesImport)
                pantry.append(created)
                try await repository.save(created)
                summary.itemsAdded += 1
            }
        }
    }

    /// One staple event per resolved item (AC-11.5). Nothing else is learned from an import.
    private func logStaples(_ items: [InboxImport.Item], now: Date) async throws {
        for item in items {
            guard let found = ingredient(for: item) else { continue }
            try await context.repositories.learningEvents.save(
                LearningEvent(
                    id: LearningEventID(context.makeID()), kind: .importedItem(ingredient: found.id), at: now))
        }
    }
}
