import Foundation
import OMPDomain
import OMPRecipes
import Testing

private func validate(
    catalog: String = SeedFixture.catalog, ingredients: String = SeedFixture.ingredients,
    recipes: String = SeedFixture.recipes
) -> SeedValidationResult {
    SeedValidator.validate(SeedFixture.files(catalog: catalog, ingredients: ingredients, recipes: recipes))
}

/// Asserts the content is rejected (no library) and reports `expected`.
private func expectRejected(
    _ result: SeedValidationResult, with expected: SeedIssue, sourceLocation: SourceLocation = #_sourceLocation
) {
    #expect(result.library == nil, sourceLocation: sourceLocation)
    #expect(result.issues.contains(expected), "issues: \(result.issues)", sourceLocation: sourceLocation)
}

@Suite("Seed validator")
struct SeedValidatorTests {
    @Test("the fixture library is valid and builds every recipe and ingredient")
    func validFixture() throws {
        let result = validate()
        #expect(result.issues == [])
        let library = try #require(result.library)
        #expect(library.contentVersion == "fixture-1")
        #expect(library.ingredients.map(\.id) == ["toor-dal", "ghee", "hing", "onion", "peanuts"])
        #expect(library.recipes.map(\.id) == ["dal-tadka", "peanut-salad"])

        let dal = try #require(library.recipe("dal-tadka"))
        #expect(dal.ingredients.count == 4)
        #expect(dal.ingredients[2] == RecipeIngredientLine(ingredientId: "hing", quantity: 0, unit: .pinch, isOptional: true))
        #expect(dal.lunchboxSuitable == false)
        #expect(dal.provenance == RecipeProvenance(source: "OffMyPlate team (original)", notes: "Test fixture"))
        let salad = try #require(library.recipe("peanut-salad"))
        #expect(salad.review == RecipeReview(status: .signedOff, reviewer: "Owner", reviewedOn: LocalDate(year: 2026, month: 10, day: 12)))

        let hing = try #require(library.ingredient("hing"))
        #expect(hing.tagStatus == .unverified)
        #expect(hing.mayContain == [.wheat, .gluten])
        #expect(library.ingredient("ghost") == nil)
    }

    @Test("derived tags are the union of tags and mayContain, optional lines included")
    func derivedTags() throws {
        let library = try #require(validate().library)
        let dal = try #require(library.recipe("dal-tadka"))
        #expect(library.derivedTags(of: dal) == [.milk, .wheat, .gluten, .onion])
        #expect(library.unverifiedIngredients(of: dal).map(\.id) == ["hing"])
        let salad = try #require(library.recipe("peanut-salad"))
        #expect(library.derivedTags(of: salad) == [.peanut, .onion])
        #expect(library.unverifiedIngredients(of: salad).isEmpty)
    }

    @Test("catalog: restrictions in file order, keywords select restrictions case-insensitively")
    func catalog() throws {
        let catalog = try #require(validate().library).catalog
        #expect(catalog.restrictions.map(\.id) == ["peanuts", "jain"])
        #expect(catalog.restrictions(forKeyword: "  Nuts ").map(\.id) == ["peanuts"])
        #expect(catalog.restrictions(forKeyword: "cashew").isEmpty)
        #expect(catalog.aisles == Aisle.allCases)
        #expect(catalog.foodTagLabelKeys.count == FoodTag.allCases.count)
        #expect(catalog.aisleLabelKeys[.oilsAndGhee] == "aisle.oilsAndGhee")
        #expect(catalog.cuisines.map(\.id) == ["northIndian", "westIndian"])
    }

    // MARK: Defect classes required by T04

    @Test("rejects a recipe line whose ingredient does not exist (dangling id)")
    func danglingIngredient() throws {
        let recipes = try SeedFixture.mutated(
            SeedFixture.recipes, replacing: #""ingredientId": "toor-dal""#, with: #""ingredientId": "ghost-dal""#)
        expectRejected(validate(recipes: recipes), with: .danglingIngredient(recipe: "dal-tadka", ingredient: "ghost-dal"))
    }

    @Test("rejects declaredTags that miss a derived tag (hing's wheat and gluten)")
    func declaredTagsMissingDerived() throws {
        let recipes = try SeedFixture.mutated(
            SeedFixture.recipes, replacing: #""declaredTags": ["milk", "wheat", "gluten", "onion"]"#,
            with: #""declaredTags": ["milk", "onion"]"#)
        expectRejected(
            validate(recipes: recipes),
            with: .declaredTagsMismatch(recipe: "dal-tadka", undeclared: [.wheat, .gluten], unsupported: []))
    }

    @Test("rejects declaredTags that claim a tag no ingredient has")
    func declaredTagsExtra() throws {
        let recipes = try SeedFixture.mutated(
            SeedFixture.recipes, replacing: #""declaredTags": ["peanut", "onion"]"#,
            with: #""declaredTags": ["peanut", "onion", "egg"]"#)
        expectRejected(
            validate(recipes: recipes), with: .declaredTagsMismatch(recipe: "peanut-salad", undeclared: [], unsupported: [.egg]))
    }

    @Test("rejects an ingredient tag change that the recipe does not declare (two-sided check)")
    func ingredientTagChangeBreaksRecipe() throws {
        let ingredients = try SeedFixture.mutated(
            SeedFixture.ingredients, replacing: #""tags": ["onion"]"#, with: #""tags": ["onion", "rootVegetable"]"#)
        let result = validate(ingredients: ingredients)
        expectRejected(
            result, with: .declaredTagsMismatch(recipe: "dal-tadka", undeclared: [.rootVegetable], unsupported: []))
        #expect(result.issues.contains(.declaredTagsMismatch(recipe: "peanut-salad", undeclared: [.rootVegetable], unsupported: [])))
    }

    @Test("rejects an ingredient without an aisle")
    func missingAisle() throws {
        let ingredients = try SeedFixture.mutated(SeedFixture.ingredients, replacing: #""aisle": "oilsAndGhee", "#, with: "")
        expectRejected(validate(ingredients: ingredients), with: .missingField(.ingredient, id: "ghee", field: "aisle"))
    }

    @Test("rejects an ingredient with an unknown aisle")
    func unknownAisle() throws {
        let ingredients = try SeedFixture.mutated(
            SeedFixture.ingredients, replacing: #""aisle": "oilsAndGhee""#, with: #""aisle": "fats""#)
        expectRejected(
            validate(ingredients: ingredients), with: .unknownValue(.ingredient, id: "ghee", field: "aisle", value: "fats"))
    }

    @Test("rejects an ingredient without a tagStatus (A3: unknown tags are never assumed safe)")
    func missingTagStatus() throws {
        let ingredients = try SeedFixture.mutated(SeedFixture.ingredients, replacing: #""tagStatus": "unverified", "#, with: "")
        expectRejected(validate(ingredients: ingredients), with: .missingField(.ingredient, id: "hing", field: "tagStatus"))
    }

    @Test("rejects an ingredient without a tags list")
    func missingTags() throws {
        let ingredients = try SeedFixture.mutated(SeedFixture.ingredients, replacing: #""tags": ["onion"], "#, with: "")
        expectRejected(validate(ingredients: ingredients), with: .missingField(.ingredient, id: "onion", field: "tags"))
    }

    @Test("rejects an unknown food tag on an ingredient")
    func unknownTag() throws {
        let ingredients = try SeedFixture.mutated(SeedFixture.ingredients, replacing: #""tags": ["milk"]"#, with: #""tags": ["dairy"]"#)
        expectRejected(
            validate(ingredients: ingredients), with: .unknownValue(.ingredient, id: "ghee", field: "tags", value: "dairy"))
    }

    @Test("rejects an unknown unit on a recipe line")
    func unknownRecipeUnit() throws {
        let recipes = try SeedFixture.mutated(SeedFixture.recipes, replacing: #""unit": "tbsp""#, with: #""unit": "handful""#)
        expectRejected(
            validate(recipes: recipes),
            with: .unknownValue(.recipe, id: "dal-tadka", field: "ingredients[1].unit", value: "handful"))
    }

    @Test("rejects an unknown default unit on an ingredient")
    func unknownDefaultUnit() throws {
        let ingredients = try SeedFixture.mutated(
            SeedFixture.ingredients, replacing: #""defaultUnit": "pinch""#, with: #""defaultUnit": "chutki""#)
        expectRejected(
            validate(ingredients: ingredients),
            with: .unknownValue(.ingredient, id: "hing", field: "defaultUnit", value: "chutki"))
    }

    @Test("rejects a duplicate ingredient id")
    func duplicateIngredientID() throws {
        let ingredients = try SeedFixture.mutated(SeedFixture.ingredients, replacing: #""id": "peanuts""#, with: #""id": "ghee""#)
        expectRejected(validate(ingredients: ingredients), with: .duplicateID(.ingredient, id: "ghee"))
    }

    @Test("rejects a duplicate recipe id")
    func duplicateRecipeID() throws {
        let recipes = try SeedFixture.mutated(SeedFixture.recipes, replacing: #""id": "peanut-salad""#, with: #""id": "dal-tadka""#)
        expectRejected(validate(recipes: recipes), with: .duplicateID(.recipe, id: "dal-tadka"))
    }

    @Test("rejects a duplicate restriction id in the catalog")
    func duplicateRestrictionID() throws {
        let catalog = try SeedFixture.mutated(SeedFixture.catalog, replacing: #""id": "jain""#, with: #""id": "peanuts""#)
        expectRejected(validate(catalog: catalog), with: .duplicateID(.restriction, id: "peanuts"))
    }

    @Test("rejects a restriction with an empty excludedTags list")
    func restrictionWithoutTags() throws {
        let catalog = try SeedFixture.mutated(SeedFixture.catalog, replacing: #""excludedTags": ["peanut"]"#, with: #""excludedTags": []"#)
        expectRejected(validate(catalog: catalog), with: .missingField(.restriction, id: "peanuts", field: "excludedTags"))
    }

    @Test("rejects a restriction without an excludedTags field")
    func restrictionMissingTagsField() throws {
        let catalog = try SeedFixture.mutated(SeedFixture.catalog, replacing: #", "excludedTags": ["peanut"]"#, with: "")
        expectRejected(validate(catalog: catalog), with: .missingField(.restriction, id: "peanuts", field: "excludedTags"))
    }

    @Test("rejects a restriction that excludes an unknown tag")
    func restrictionUnknownTag() throws {
        let catalog = try SeedFixture.mutated(SeedFixture.catalog, replacing: #""excludedTags": ["peanut"]"#, with: #""excludedTags": ["peanut", "nuts"]"#)
        let result = validate(catalog: catalog)
        expectRejected(result, with: .unknownValue(.restriction, id: "peanuts", field: "excludedTags", value: "nuts"))
        #expect(!result.issues.contains(.missingField(.restriction, id: "peanuts", field: "excludedTags")))
    }

    // MARK: Further structural checks

    @Test("rejects a quantified line for an ingredient whose default unit is unquantified")
    func quantifiedLineForUnquantifiedDefault() throws {
        let recipes = try SeedFixture.mutated(
            SeedFixture.recipes, replacing: #"{"ingredientId": "hing", "unit": "pinch", "optional": true}"#,
            with: #"{"ingredientId": "hing", "quantity": 1, "unit": "g", "optional": true}"#)
        expectRejected(validate(recipes: recipes), with: .unconvertibleUnit(recipe: "dal-tadka", ingredient: "hing", unit: .gram))
    }

    @Test("rejects a quantified line whose unit cannot be converted for the ingredient")
    func unconvertibleUnit() throws {
        let recipes = try SeedFixture.mutated(
            SeedFixture.recipes, replacing: #"{"ingredientId": "peanuts", "quantity": 100, "unit": "g"}"#,
            with: #"{"ingredientId": "peanuts", "quantity": 2, "unit": "tbsp"}"#)
        expectRejected(
            validate(recipes: recipes), with: .unconvertibleUnit(recipe: "peanut-salad", ingredient: "peanuts", unit: .tablespoon))
    }

    @Test("rejects a quantified line without a positive quantity")
    func nonPositiveQuantity() throws {
        let recipes = try SeedFixture.mutated(
            SeedFixture.recipes, replacing: #""quantity": 150, "#, with: #""quantity": 0, "#)
        expectRejected(
            validate(recipes: recipes),
            with: .invalidValue(.recipe, id: "dal-tadka", field: "ingredients[0].quantity", detail: "must be a positive number for unit 'g'"))
    }

    @Test("rejects a recipe region that is not a catalog cuisine")
    func unknownRegion() throws {
        let recipes = try SeedFixture.mutated(SeedFixture.recipes, replacing: #""region": "westIndian""#, with: #""region": "mars""#)
        expectRejected(validate(recipes: recipes), with: .unknownValue(.recipe, id: "peanut-salad", field: "region", value: "mars"))
    }

    @Test("rejects a signed-off recipe without a reviewer")
    func signedOffWithoutReviewer() throws {
        let recipes = try SeedFixture.mutated(SeedFixture.recipes, replacing: #""reviewer": "Owner", "#, with: "")
        expectRejected(
            validate(recipes: recipes),
            with: .invalidValue(.recipe, id: "peanut-salad", field: "review", detail: "signedOff needs a reviewer and reviewedOn"))
    }

    @Test("rejects two ingredients that share a name or synonym")
    func ambiguousSynonym() throws {
        let ingredients = try SeedFixture.mutated(
            SeedFixture.ingredients, replacing: #""synonyms": ["arhar dal"]"#, with: #""synonyms": ["Groundnuts"]"#)
        expectRejected(validate(ingredients: ingredients), with: .ambiguousName("groundnuts", ingredients: ["peanuts", "toor-dal"]))
    }

    @Test("rejects a catalog that omits a food tag")
    func catalogMissingFoodTag() throws {
        let catalog = try SeedFixture.mutated(
            SeedFixture.catalog, replacing: #"{"id": "gelatin", "labelKey": "foodTag.gelatin"}, "#, with: "")
        expectRejected(validate(catalog: catalog), with: .catalogIncomplete(field: "foodTags", missing: ["gelatin"]))
    }

    @Test("rejects a keyword that points at an unknown restriction")
    func danglingKeyword() throws {
        let catalog = try SeedFixture.mutated(SeedFixture.catalog, replacing: #""nuts": ["peanuts"]"#, with: #""nuts": ["peanuts", "treeNuts"]"#)
        expectRejected(validate(catalog: catalog), with: .danglingRestriction(keyword: "nuts", restriction: "treeNuts"))
    }

    @Test("rejects an unsupported schema version and a content version that differs from the catalog's")
    func headers() throws {
        let ingredients = try SeedFixture.mutated(SeedFixture.ingredients, replacing: #""schemaVersion": 1"#, with: #""schemaVersion": 2"#)
        expectRejected(validate(ingredients: ingredients), with: .unsupportedSchemaVersion(.ingredients, found: 2))
        let recipes = try SeedFixture.mutated(SeedFixture.recipes, replacing: #""contentVersion": "fixture-1""#, with: #""contentVersion": "fixture-0""#)
        expectRejected(
            validate(recipes: recipes), with: .contentVersionMismatch(.recipes, found: "fixture-0", expected: "fixture-1"))
    }

    @Test("reports malformed JSON per file instead of crashing")
    func malformedJSON() {
        let result = validate(recipes: "{ not json")
        #expect(result.library == nil)
        #expect(result.issues.count == 1)
        if case .malformedFile(let file, _)? = result.issues.first {
            #expect(file == .recipes)
        } else {
            Issue.record("expected malformedFile, got \(result.issues)")
        }
    }

    @Test("SeedLoader.load throws every issue for invalid content")
    func loaderThrows() throws {
        let recipes = try SeedFixture.mutated(
            SeedFixture.recipes, replacing: #""ingredientId": "toor-dal""#, with: #""ingredientId": "ghost-dal""#)
        #expect(throws: SeedLoadError.invalid([.danglingIngredient(recipe: "dal-tadka", ingredient: "ghost-dal")])) {
            try SeedLoader.load(SeedFixture.files(recipes: recipes))
        }
    }
}
