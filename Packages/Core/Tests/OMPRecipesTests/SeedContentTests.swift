import Foundation
import OMPDomain
import OMPRecipes
import Testing

/// T06: the 30 bundled seed recipes (A2, G1, G5). Checks the split, the sign-off state and that
/// every restriction chip still leaves something to cook in every planned slot.
///
/// "Allowed" uses the planner's hard filter (plan section 7 step 3, AC-4.3): a recipe is allowed
/// for a household rule when none of its derived tags (tags plus "may contain", optional lines
/// included) is excluded by the rule AND none of its ingredients is unverified, because any hard
/// rule excludes recipes with unverified ingredients.
@Suite("Bundled seed recipes (T06)")
struct SeedContentTests {
    /// The plan slots v1 fills (G5 default: breakfast, lunch, dinner and the lunchbox subset;
    /// snacks are off by default).
    enum Slot: String, CaseIterable, CustomStringConvertible {
        case breakfast, lunch, dinner, lunchbox

        var description: String { rawValue }

        func fits(_ recipe: Recipe) -> Bool {
            switch self {
            case .breakfast: return recipe.mealTypes.contains(.breakfast)
            case .lunch: return recipe.mealTypes.contains(.lunch)
            case .dinner: return recipe.mealTypes.contains(.dinner)
            case .lunchbox: return recipe.lunchboxSuitable
            }
        }
    }

    /// Restriction/slot combinations known to have no recipe. Empty for content 2026.10.13-t06:
    /// every single chip and every pair of chips leaves at least one recipe in every slot.
    /// If content changes open a gap, list it here (it is then reported to the owner) rather
    /// than weakening the checks below.
    static let knownGaps: Set<String> = []

    private static func library() throws -> SeedLibrary {
        try SeedLoader.loadBundled()
    }

    private static func allowed(_ recipe: Recipe, excluding excluded: Set<FoodTag>, in library: SeedLibrary) -> Bool {
        library.derivedTags(of: recipe).isDisjoint(with: excluded) && library.unverifiedIngredients(of: recipe).isEmpty
    }

    private static func count(
        _ slot: Slot, excluding excluded: Set<FoodTag>, in library: SeedLibrary
    ) -> Int {
        library.recipes.filter { slot.fits($0) && allowed($0, excluding: excluded, in: library) }.count
    }

    @Test("the 30 recipes pass the validator, are drafts awaiting sign-off and record original provenance")
    func validatesAsDrafts() throws {
        let result = SeedValidator.validate(try SeedLoader.bundledFiles())
        #expect(result.issues == [], "\(result.issues.map(\.description).joined(separator: "\n"))")
        let library = try #require(result.library)
        #expect(library.recipes.count == 30)
        for recipe in library.recipes {
            #expect(recipe.review.status == .draft, "\(recipe.id)")
            #expect(recipe.review.reviewer == nil, "\(recipe.id)")
            #expect(recipe.provenance.source == "original (OffMyPlate team)", "\(recipe.id)")
            #expect(recipe.servings == 4, "\(recipe.id)")
            #expect(recipe.steps.count >= 3, "\(recipe.id)")
        }
    }

    @Test("G1 split: 8 breakfast, 14 lunch/dinner mains, 8 lunchbox-suitable, with no overlap")
    func split() throws {
        let recipes = try Self.library().recipes
        let breakfast = recipes.filter { $0.mealTypes.contains(.breakfast) }
        let lunchbox = recipes.filter(\.lunchboxSuitable)
        let mains = recipes.filter {
            !$0.mealTypes.isDisjoint(with: [.lunch, .dinner]) && !$0.mealTypes.contains(.breakfast) && !$0.lunchboxSuitable
        }
        #expect(breakfast.count == 8)
        #expect(mains.count == 14)
        #expect(lunchbox.count == 8)
        #expect(breakfast.count + mains.count + lunchbox.count == recipes.count)
        #expect(lunchbox.allSatisfy { !$0.mealTypes.contains(.breakfast) }, "lunchbox and breakfast overlap")
        #expect(lunchbox.allSatisfy { $0.mealTypes.contains(.lunch) }, "a lunchbox recipe should also be a lunch")
    }

    @Test("owner context: the library is mostly Kerala dishes")
    func mostlyKerala() throws {
        let recipes = try Self.library().recipes
        let kerala = recipes.filter { $0.region == "kerala" }
        #expect(kerala.count * 4 >= recipes.count * 3, "only \(kerala.count) of \(recipes.count) are Kerala")
    }

    @Test("every restriction chip leaves at least one recipe in every planned slot")
    func everyRestrictionCoversEverySlot() throws {
        let library = try Self.library()
        for restriction in library.catalog.restrictions {
            for slot in Slot.allCases where !Self.knownGaps.contains("\(restriction.id)/\(slot)") {
                let found = Self.count(slot, excluding: restriction.excludedTags, in: library)
                #expect(found >= 1, "no \(slot) recipe for '\(restriction.id)'")
            }
        }
    }

    @Test("every pair of restriction chips leaves at least one recipe in every planned slot")
    func everyRestrictionPairCoversEverySlot() throws {
        let library = try Self.library()
        let restrictions = library.catalog.restrictions
        for (index, first) in restrictions.enumerated() {
            for second in restrictions[(index + 1)...] {
                let excluded = first.excludedTags.union(second.excludedTags)
                for slot in Slot.allCases where !Self.knownGaps.contains("\(first.id)+\(second.id)/\(slot)") {
                    #expect(
                        Self.count(slot, excluding: excluded, in: library) >= 1,
                        "no \(slot) recipe for '\(first.id)' + '\(second.id)'")
                }
            }
        }
    }

    @Test("a vegetarian + Jain + nut-free household has at least one recipe per slot")
    func vegetarianJainNutHousehold() throws {
        let library = try Self.library()
        let ids: [RestrictionID] = ["vegetarian", "jain", "peanuts", "tree-nuts"]
        var excluded = Set<FoodTag>()
        for id in ids {
            excluded.formUnion(try #require(library.catalog.restriction(id), "\(id)").excludedTags)
        }
        for slot in Slot.allCases {
            #expect(Self.count(slot, excluding: excluded, in: library) >= 1, "no \(slot) recipe for this household")
        }
        // Pinned so a content change that thins this household's choice is deliberate.
        let counts = Slot.allCases.map { Self.count($0, excluding: excluded, in: library) }
        #expect(counts == [2, 7, 4, 3], "breakfast, lunch, dinner, lunchbox: \(counts)")
    }

    @Test("G5 known gap: there are no snack recipes (snacks are off by default)")
    func noSnacks() throws {
        let recipes = try Self.library().recipes
        #expect(recipes.allSatisfy { !$0.mealTypes.contains(.snack) })
    }

    @Test("AC-4.3: only the rasam uses an unverified ingredient (compounded hing)")
    func unverifiedIngredientsAreRare() throws {
        let library = try Self.library()
        let withUnverified = library.recipes.filter { !library.unverifiedIngredients(of: $0).isEmpty }
        #expect(withUnverified.map(\.id) == ["kerala-rasam"])
        let rasam = try #require(library.recipe("kerala-rasam"))
        #expect(library.unverifiedIngredients(of: rasam).map(\.id) == ["hing"])
    }

    @Test("optional lines still count: ghee rice's optional cashews make it tree-nut")
    func optionalLinesCount() throws {
        let library = try Self.library()
        let neychoru = try #require(library.recipe("neychoru"))
        #expect(neychoru.ingredients.contains { $0.ingredientId == "cashews" && $0.isOptional })
        #expect(library.derivedTags(of: neychoru).contains(.treeNut))
        #expect(neychoru.declaredTags.contains(.treeNut))
    }

    @Test("rice-flour dishes count as wheat and gluten (may contain), so puttu is not wheat-free")
    func riceFlourMayContainWheat() throws {
        let library = try Self.library()
        let puttu = try #require(library.recipe("puttu-pazham"))
        #expect(library.derivedTags(of: puttu).isSuperset(of: [.wheat, .gluten]))
        let idli = try #require(library.recipe("idli-coconut-chutney"))
        #expect(library.derivedTags(of: idli).isDisjoint(with: [.wheat, .gluten]))
    }
}
