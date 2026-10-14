import Foundation
import OMPDomain
import OMPServices
import Testing

/// A library with aisles, fridge items and an egg ingredient, for the T19 tests.
enum ServicesBFixture {
    static func ingredients() -> [Ingredient] {
        var result = ServicesFixture.ingredients().map { ingredient -> Ingredient in
            var copy = ingredient
            switch ingredient.id.rawValue {
            case "rice", "atta", "semolina", "poha-flakes":
                copy.aisle = .grainsAndFlours
            case "vegetables":
                copy.aisle = .vegetablesAndFruit
                copy.defaultLocation = .fridge
                copy.fridgeShelfLifeDays = 5
            case "curd":
                copy.aisle = .dairyAndEggs
                copy.defaultLocation = .fridge
                copy.fridgeShelfLifeDays = 4
            default:
                break
            }
            return copy
        }
        var eggs = ServicesFixture.ingredient("eggs")
        eggs.aisle = .dairyAndEggs
        eggs.defaultUnit = .piece
        eggs.defaultLocation = .fridge
        eggs.fridgeShelfLifeDays = 14
        result.append(eggs)
        return result
    }

    static func library() -> PlanningLibrary {
        PlanningLibrary(
            recipes: ServicesFixture.recipes, ingredients: ingredients(), restrictions: ServicesFixture.restrictions,
            contentVersion: "test-1")
    }

    static let rice: IngredientID = "rice"
    static let eggs: IngredientID = "eggs"

    /// An inbox file as the Share Extension would write it.
    static func inboxFile(
        id: String, destination: InboxImport.Destination = .shoppingList, items: [InboxImport.Item]
    ) throws -> (name: String, data: Data) {
        let value = try InboxImport(
            importId: InboxImportID(id), createdAt: ServicesFixture.now, destination: destination, items: items)
        return (value.fileName, try value.encoded())
    }
}

/// The T19 services over in-memory repositories and stores, sharing one `ServicesEnv`.
struct ServicesBEnv: Sendable {
    let base: ServicesEnv
    let inbox: InMemoryInboxStorage
    let processed: InMemoryProcessedImportStore
    let counters: InMemoryCounterStore
    let pantry: PantryService
    let shopping: ShoppingService
    let imports: ImportService
    let learning: LearningService
    let data: DataService

    init() {
        let base = ServicesEnv(library: ServicesBFixture.library())
        let inbox = InMemoryInboxStorage()
        let processed = InMemoryProcessedImportStore()
        let counters = InMemoryCounterStore()
        self.base = base
        self.inbox = inbox
        self.processed = processed
        self.counters = counters
        self.pantry = PantryService(context: base.context)
        self.shopping = ShoppingService(context: base.context)
        self.imports = ImportService(context: base.context, inbox: inbox, processedImports: processed)
        self.learning = LearningService(context: base.context, counters: counters)
        self.data = DataService(
            context: base.context, inbox: inbox, processedImports: processed, counters: counters)
    }

    var repositories: Repositories { base.repositories }
    var clock: TestClock { base.clock }

    func events() async throws -> [LearningEvent] {
        try await repositories.learningEvents.fetchAll()
    }

    /// The shopping lines for `ingredient` with the given origin.
    func lines(for ingredient: IngredientID, origin: ShoppingItemOrigin? = nil) async throws -> [ShoppingItem] {
        try await repositories.shopping.fetchAll().filter {
            $0.ingredientId == ingredient && (origin == nil || $0.origin == origin)
        }
    }
}

/// A spoken pantry item for `ingredient` (what the confirmation card holds).
func spoken(_ ingredient: IngredientID, qty: Double? = nil, unit: MeasureUnit? = nil) -> SpokenPantryItem {
    SpokenPantryItem(
        spokenText: ingredient.rawValue, name: ingredient.rawValue, qty: qty, unit: unit,
        match: IngredientResolver.Candidate(
            ingredientId: ingredient, name: ingredient.rawValue, matchedTerm: ingredient.rawValue, kind: .exactName),
        isConfident: true)
}
