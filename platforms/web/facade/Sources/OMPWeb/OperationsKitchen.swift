import Foundation
import OMPDomain
import OMPServices

// W13: pantry, Mark cooked, shopping list, Notes import, learning and data operations.
//
// Same rules as Operations.swift: every case calls a service; nothing here plans, approves or touches a
// safety rule. In particular the import path (`import.confirm`) goes through `ImportService`, which has no
// access to rules, members or safety status, and Mark cooked is refused by the core for any plan that is
// not effectively approved. Every number a client sends is bounded before it reaches a service.

extension FacadeSession {
    /// Returns nil when `request.op` is not one of the W13 operations.
    func dispatchKitchen(_ request: Request, engine: Engine, content: SeedContent) async throws -> Data? {
        switch request.op {
        // MARK: pantry (AC-9.1 ... AC-9.7)
        case "pantry.list":
            return try await pantryList(engine)
        case "pantry.search":
            struct Args: Decodable { var query: String; var limit: Int? }
            let args = try request.decode(Args.self)
            try Limits.require(args.query.count <= Limits.maxNameCharacters, "The search text is too long.")
            let limit = min(max(args.limit ?? 10, 1), Limits.maxSearchResults)
            let found = engine.pantry.searchIngredients(args.query, limit: limit)
            return try enc(
                IngredientSearchView(
                    candidates: found.map {
                        IngredientCandidateView(
                            ingredientId: $0.ingredientId, name: $0.name, matchedTerm: $0.matchedTerm,
                            kind: String(describing: $0.kind))
                    }))
        case "pantry.add":
            let input = try request.decode(PantryItemArgs.self).input(content: content)
            let item = try await engine.pantry.add(input)
            return try enc(PantryItemResultView(item: pantryRow(item, engine)))
        case "pantry.update":
            let id = try request.decode(PantryItemIDArg.self).itemId
            let input = try request.decode(PantryItemArgs.self).input(content: content)
            let item = try await engine.pantry.update(id, with: input)
            return try enc(PantryItemResultView(item: pantryRow(item, engine)))
        case "pantry.resolve":
            struct Args: Decodable { var itemId: PantryItemID; var ingredientId: IngredientID }
            let args = try request.decode(Args.self)
            let item = try await engine.pantry.resolve(args.itemId, to: args.ingredientId)
            return try enc(PantryItemResultView(item: pantryRow(item, engine)))
        case "pantry.reconfirm":
            let id = try request.decode(PantryItemIDArg.self).itemId
            let item = try await engine.pantry.reconfirm(id)
            return try enc(PantryItemResultView(item: pantryRow(item, engine)))
        case "pantry.delete":
            let id = try request.decode(PantryItemIDArg.self).itemId
            try await engine.pantry.delete(id)
            return try enc(DeletedView(deleted: true))

        // MARK: Mark cooked (AC-9.6): the core refuses anything but an effectively approved plan
        case "cook.propose":
            struct Args: Decodable { var planId: MealPlanID; var mealId: PlannedMealID }
            let args = try request.decode(Args.self)
            let amounts = try await engine.pantry.proposedCookAmounts(plan: args.planId, meal: args.mealId)
            return try enc(CookAmountsView(amounts: amounts.map(CookAmountView.init)))
        case "cook.mark":
            struct Args: Decodable {
                var planId: MealPlanID
                var mealId: PlannedMealID
                var amounts: [CookAmountArg]?
            }
            let args = try request.decode(Args.self)
            try Limits.require((args.amounts?.count ?? 0) <= Limits.maxCookAmounts, "Too many amounts.")
            let edited = try args.amounts?.map { try $0.cookAmount(content: content) }
            let log = try await engine.pantry.markCooked(plan: args.planId, meal: args.mealId, amounts: edited)
            guard let plan = try await engine.repositories.mealPlans.fetch(id: args.planId) else {
                throw ServiceError.planNotFound(args.planId)
            }
            return try enc(CookedView(cookLog: log, plan: PlanView(plan)))

        // MARK: shopping list (AC-10.x)
        case "shopping.list":
            return try enc(ShoppingListView(items: try await engine.shopping.items()))
        case "shopping.refresh":
            return try enc(ShoppingListView(items: try await engine.shopping.refresh()))
        case "shopping.add":
            struct Args: Decodable {
                var name: String
                var ingredientId: IngredientID?
                var quantity: Double?
                var unit: MeasureUnit?
            }
            let args = try request.decode(Args.self)
            try Self.checkName(args.name)
            try Self.checkIngredient(args.ingredientId, content)
            if let quantity = args.quantity { try Self.checkAmount(quantity) }
            let item = try await engine.shopping.addManual(
                ShoppingItemInput(
                    name: args.name, ingredientId: args.ingredientId, quantity: args.quantity, unit: args.unit))
            return try enc(ShoppingItemResultView(item: item))
        case "shopping.check":
            struct Args: Decodable { var itemId: ShoppingItemID; var checked: Bool }
            let args = try request.decode(Args.self)
            return try enc(
                ShoppingItemResultView(item: try await engine.shopping.setChecked(args.itemId, args.checked)))
        case "shopping.remove":
            struct Args: Decodable { var itemId: ShoppingItemID }
            let args = try request.decode(Args.self)
            try await engine.shopping.remove(args.itemId)
            return try enc(DeletedView(deleted: true))
        case "shopping.boughtEverything":
            let added = try await engine.shopping.boughtEverything()
            let list = try await engine.shopping.items()
            let rows = added.map { pantryRow($0, engine) }
            return try enc(BoughtView(pantryAdded: rows, items: list))
        case "shopping.shareText":
            return try enc(ShareTextView(text: try await engine.shopping.shareText()))

        // MARK: Notes import (AC-11.x): text or file bytes in, staple events only, never rules
        case "import.parseText":
            struct Args: Decodable { var text: String }
            let args = try request.decode(Args.self)
            try Limits.require(args.text.utf8.count <= Limits.maxImportBytes, "The pasted text is too large.")
            return try enc(importPreview(of: args.text, content: content))
        case "import.parseFile":
            // The browser reads the file and sends its bytes base64-encoded; only UTF-8 text is accepted.
            struct Args: Decodable { var base64: String }
            let args = try request.decode(Args.self)
            try Limits.require(args.base64.utf8.count <= Limits.maxBase64Characters, "The file is too large.")
            guard let bytes = Data(base64Encoded: args.base64) else { throw FacadeError.invalid("The file bytes are not valid base64.") }
            try Limits.require(bytes.count <= Limits.maxImportBytes, "The file is too large.")
            guard !bytes.contains(0), var text = String(data: bytes, encoding: .utf8) else {
                throw FacadeError("not_text", "Only plain text files can be imported.")
            }
            if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
            return try enc(importPreview(of: text, content: content))
        case "import.confirm":
            struct Args: Decodable { var destination: InboxImport.Destination; var items: [ImportItemArg] }
            let args = try request.decode(Args.self)
            return try await confirmImport(args.destination, args.items, engine: engine, content: content)

        // MARK: learning (AC-12.x): soft facts only
        case "learning.list":
            return try enc(FactListView(facts: try await engine.learning.learned().map(FactView.init)))
        case "learning.refresh":
            _ = try await engine.learning.refresh()
            return try enc(FactListView(facts: try await engine.learning.learned().map(FactView.init)))
        case "learning.reflectBack":
            return try enc(FactResultView(fact: try await engine.learning.nextReflectBack().map(FactView.init)))
        case "learning.answer":
            struct Args: Decodable { var factId: FactID; var answer: ReflectBackAnswer }
            let args = try request.decode(Args.self)
            return try await answerReflectBack(engine, args.factId, args.answer)
        case "learning.confirm":
            // "Yes" on the reflect-back card (AC-12.3): confirms the soft fact.
            struct Args: Decodable { var factId: FactID }
            let args = try request.decode(Args.self)
            return try await answerReflectBack(engine, args.factId, .yes)
        case "learning.forget":
            struct Args: Decodable { var factId: FactID }
            let args = try request.decode(Args.self)
            return try enc(FactResultView(fact: FactView(try await engine.learning.forget(args.factId))))

        // MARK: data (AC-16.x)
        case "data.prune":
            let cutoff = try await engine.data.prune()
            return try enc(PrunedView(cutoff: cutoff))
        case "data.deleteAll":
            // Removes every stored entity, the import records and the counters, then starts from a new,
            // empty engine (ids restart, so the next export is a brand-new state).
            struct Args: Decodable { var confirmed: Bool }
            let args = try request.decode(Args.self)
            guard args.confirmed else {
                throw FacadeError("confirmation_required", "Deleting all data needs the person's confirmation.")
            }
            try await engine.data.deleteAll()
            replaceEngine(Engine(repositories: .inMemory(), clock: clock, ids: IDSource(), content: content))
            return try enc(DeletedView(deleted: true))

        default:
            return nil
        }
    }

    // MARK: Helpers

    private func pantryList(_ engine: Engine) async throws -> Data {
        let items = try await engine.pantry.items()
        return try enc(PantryListView(items: items.map { pantryRow($0, engine) }))
    }

    private func pantryRow(_ item: PantryItem, _ engine: Engine) -> PantryRowView {
        let clock = engine.context.clock
        return PantryRowView(
            item: item, confidence: item.confidence(now: clock.now, timeZone: clock.timeZone),
            expired: item.isExpired(today: clock.today))
    }

    private func answerReflectBack(_ engine: Engine, _ id: FactID, _ answer: ReflectBackAnswer) async throws -> Data {
        guard let fact = try await engine.learning.allFacts().first(where: { $0.id == id }) else {
            throw ServiceError.factNotFound(id)
        }
        guard fact.status == .proposed || fact.status == .active else {
            throw FacadeError("fact_not_open", "That fact is not waiting for an answer.")
        }
        let updated = try await engine.learning.answerReflectBack(fact.key, answer)
        return try enc(FactResultView(fact: updated.map(FactView.init)))
    }

    private func importPreview(of text: String, content: SeedContent) -> ImportPreviewView {
        let parsed = ShoppingTextParser.parse(text)
        let lines = parsed.lines.map { line -> ImportLineView in
            let match = content.library.resolver.confidentMatch(for: line.name)
            return ImportLineView(
                lineIndex: line.lineIndex, rawLine: line.rawLine, name: line.name, quantity: line.qty, unit: line.unit,
                checked: line.wasChecked, confidence: line.confidence.rawValue, selected: line.isSelectedByDefault,
                ingredientId: match?.ingredientId, ingredientName: match?.name)
        }
        return ImportPreviewView(lines: lines, truncated: parsed.wasTruncated)
    }

    /// Builds the same inbox document the iOS Share Extension writes, puts it in the session's inbox and
    /// lets `ImportService` merge it (shopping list or pantry, one `.importedItem` event per resolved item).
    private func confirmImport(
        _ destination: InboxImport.Destination, _ items: [ImportItemArg], engine: Engine, content: SeedContent
    ) async throws -> Data {
        try Limits.require(!items.isEmpty, "Choose at least one item to import.")
        try Limits.require(items.count <= InboxImport.maxItems, "Too many items.")
        let converted = try items.map { try $0.inboxItem(content: content) }
        let id = InboxImportID(engine.ids.next())
        let document = try InboxImport(
            importId: id, createdAt: engine.context.clock.now, destination: destination, items: converted)
        await engine.inbox.put(document.fileName, try document.encoded())
        let summary = try await engine.imports.drainInbox()
        return try enc(ImportSummaryView(summary))
    }

    static func checkName(_ name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        try Limits.require(!trimmed.isEmpty, "A name is required.")
        try Limits.require(name.count <= Limits.maxNameCharacters, "The name is too long.")
    }

    static func checkAmount(_ value: Double) throws {
        try Limits.require(value.isFinite && value >= 0 && value <= Limits.maxAmount, "The amount is out of range.")
    }

    static func checkIngredient(_ id: IngredientID?, _ content: SeedContent) throws {
        if let id, content.library.ingredientsByID[id] == nil {
            throw FacadeError("unknown_ingredient", "That ingredient is not in the taxonomy.")
        }
    }
}

// MARK: Arguments

struct PantryItemIDArg: Decodable { var itemId: PantryItemID }

struct PantryItemArgs: Decodable {
    var name: String
    var ingredientId: IngredientID?
    var quantity: Double
    var unit: MeasureUnit
    var location: StorageLocation
    var expiresOn: LocalDate?

    func input(content: SeedContent) throws -> PantryItemInput {
        try FacadeSession.checkName(name)
        try FacadeSession.checkIngredient(ingredientId, content)
        try FacadeSession.checkAmount(quantity)
        if let expiresOn {
            try Limits.require(
                (Limits.earliestYear...Limits.latestYear).contains(expiresOn.year), "The expiry date is out of range.")
        }
        return PantryItemInput(
            name: name, ingredientId: ingredientId, quantity: quantity, unit: unit, location: location,
            expiresOn: expiresOn)
    }
}

struct CookAmountArg: Decodable {
    var ingredientId: IngredientID
    var amount: Double
    var unit: MeasureUnit

    func cookAmount(content: SeedContent) throws -> CookAmount {
        try FacadeSession.checkIngredient(ingredientId, content)
        try FacadeSession.checkAmount(amount)
        return CookAmount(ingredientId: ingredientId, quantity: Quantity(amount, unit))
    }
}

struct ImportItemArg: Decodable {
    var name: String
    var ingredientId: IngredientID?
    var quantity: Double?
    var unit: MeasureUnit?

    func inboxItem(content: SeedContent) throws -> InboxImport.Item {
        try FacadeSession.checkName(name)
        try FacadeSession.checkIngredient(ingredientId, content)
        if let quantity {
            try Limits.require(
                quantity.isFinite && quantity > 0 && quantity <= InboxImport.Item.maxQuantity,
                "The amount is out of range.")
        }
        return InboxImport.Item(name: name, ingredientId: ingredientId, quantity: quantity, unit: unit)
    }
}

// MARK: Views

struct DeletedView: Encodable { var deleted: Bool }

struct PrunedView: Encodable { var cutoff: Date }

struct PantryRowView: Encodable, Sendable {
    var item: PantryItem
    /// Derived: "confident" or "low" (AC-9.7); the UI must not recompute it.
    var confidence: PantryConfidence
    var expired: Bool
}

struct PantryListView: Encodable { var items: [PantryRowView] }

struct PantryItemResultView: Encodable { var item: PantryRowView }

struct IngredientCandidateView: Encodable {
    var ingredientId: IngredientID
    var name: String
    var matchedTerm: String
    var kind: String
}

struct IngredientSearchView: Encodable { var candidates: [IngredientCandidateView] }

struct CookAmountView: Encodable {
    var ingredientId: IngredientID
    var amount: Double
    var unit: MeasureUnit

    init(_ amount: CookAmount) {
        ingredientId = amount.ingredientId
        self.amount = amount.quantity.amount
        unit = amount.quantity.unit
    }
}

struct CookAmountsView: Encodable { var amounts: [CookAmountView] }

struct CookedView: Encodable {
    var cookLog: CookLog
    var plan: PlanView
}

struct ShoppingListView: Encodable { var items: [ShoppingItem] }

struct ShoppingItemResultView: Encodable { var item: ShoppingItem }

struct BoughtView: Encodable {
    var pantryAdded: [PantryRowView]
    var items: [ShoppingItem]
}

struct ShareTextView: Encodable { var text: String }

struct ImportLineView: Encodable {
    var lineIndex: Int
    var rawLine: String
    var name: String
    var quantity: Double?
    var unit: MeasureUnit?
    var checked: Bool
    /// "item" or "unsure".
    var confidence: String
    var selected: Bool
    var ingredientId: IngredientID?
    var ingredientName: String?
}

struct ImportPreviewView: Encodable {
    var lines: [ImportLineView]
    var truncated: Bool
}

struct ImportSummaryView: Encodable {
    var itemsAdded: Int
    var itemsMerged: Int
    var itemsTotal: Int
    var filesImported: Int
    var alreadyImported: Int
    var quarantined: [String]
    var stuck: [String]
    var deferred: Int
    var amountsSkipped: Int
    /// Sorted (a Swift Set encodes in random order).
    var destinations: [String]

    init(_ summary: ImportSummary) {
        itemsAdded = summary.itemsAdded
        itemsMerged = summary.itemsMerged
        itemsTotal = summary.itemsTotal
        filesImported = summary.filesImported
        alreadyImported = summary.alreadyImported
        quarantined = summary.quarantined
        stuck = summary.stuck
        deferred = summary.deferred
        amountsSkipped = summary.amountsSkipped
        destinations = summary.destinations.map(\.rawValue).sorted()
    }
}

struct FactView: Encodable, Sendable {
    var id: FactID
    var subject: FactSubject
    var statement: FactStatement
    var origin: FactOrigin
    var status: FactStatus
    var suppressed: Bool
    /// Rounded to 3 decimals: the learner uses exp/pow, whose last digit may differ between platforms.
    var confidence: Double
    var forgottenAt: Date?
    var createdAt: Date
    var updatedAt: Date

    init(_ fact: Fact) {
        id = fact.id
        subject = fact.subject
        statement = fact.statement
        origin = fact.origin
        status = fact.status
        suppressed = fact.suppressed
        confidence = fact.confidence.isFinite ? (fact.confidence * 1000).rounded() / 1000 : 0
        forgottenAt = fact.forgottenAt
        createdAt = fact.createdAt
        updatedAt = fact.updatedAt
    }
}

struct FactListView: Encodable { var facts: [FactView] }

struct FactResultView: Encodable { var fact: FactView? }
