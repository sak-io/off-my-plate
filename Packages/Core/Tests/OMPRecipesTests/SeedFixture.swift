import Foundation
import OMPDomain
import OMPRecipes
import Testing

/// A small, valid seed library written as JSON text, so tests exercise the real decode path.
/// Defect tests change one substring with `mutated(_:replacing:with:)`.
enum SeedFixture {
    static let catalog: String = {
        let tags = FoodTag.allCases.map { #"{"id": "\#($0.rawValue)", "labelKey": "foodTag.\#($0.rawValue)"}"# }
        let aisles = Aisle.allCases.map { #"{"id": "\#($0.rawValue)", "labelKey": "aisle.\#($0.rawValue)"}"# }
        return """
            {"schemaVersion": 1, "contentVersion": "fixture-1",
             "foodTags": [\(tags.joined(separator: ", "))],
             "aisles": [\(aisles.joined(separator: ", "))],
             "cuisines": [{"id": "northIndian", "labelKey": "cuisine.northIndian"}, {"id": "westIndian", "labelKey": "cuisine.westIndian"}],
             "restrictions": [
              {"id": "peanuts", "labelKey": "restriction.peanuts", "excludedTags": ["peanut"]},
              {"id": "jain", "labelKey": "restriction.jain", "excludedTags": ["egg", "rootVegetable", "onion", "garlic", "mushroom"]}],
             "restrictionKeywords": {"nuts": ["peanuts"], "groundnut": ["peanuts"]}}
            """
    }()

    static let ingredients = """
        {"schemaVersion": 1, "contentVersion": "fixture-1", "ingredients": [
        {"id": "toor-dal", "name": "Toor dal", "synonyms": ["arhar dal"], "tags": [], "tagStatus": "verified", "aisle": "pulsesAndLentils", "defaultUnit": "g", "defaultLocation": "shelf"},
        {"id": "ghee", "name": "Ghee", "synonyms": ["clarified butter"], "tags": ["milk"], "tagStatus": "verified", "aisle": "oilsAndGhee", "defaultUnit": "g", "gramsPerMl": 0.91, "defaultLocation": "shelf"},
        {"id": "hing", "name": "Asafoetida", "synonyms": ["hing"], "tags": [], "mayContain": ["wheat", "gluten"], "tagStatus": "unverified", "aisle": "spicesAndMasalas", "defaultUnit": "pinch", "defaultLocation": "shelf"},
        {"id": "onion", "name": "Onion", "tags": ["onion"], "tagStatus": "verified", "aisle": "vegetablesAndFruit", "defaultUnit": "piece", "gramsPerPiece": 150, "defaultLocation": "shelf"},
        {"id": "peanuts", "name": "Peanuts", "synonyms": ["groundnuts"], "tags": ["peanut"], "tagStatus": "verified", "aisle": "other", "defaultUnit": "g", "defaultLocation": "shelf", "fridgeShelfLifeDays": 90}
        ]}
        """

    static let recipes = """
        {"schemaVersion": 1, "contentVersion": "fixture-1", "recipes": [
        {"id": "dal-tadka", "title": "Dal tadka", "region": "northIndian", "mealTypes": ["lunch", "dinner"], "servings": 4, "prepMinutes": 10, "cookMinutes": 25,
         "ingredients": [{"ingredientId": "toor-dal", "quantity": 150, "unit": "g"}, {"ingredientId": "ghee", "quantity": 1, "unit": "tbsp"}, {"ingredientId": "hing", "unit": "pinch", "optional": true}, {"ingredientId": "onion", "quantity": 1, "unit": "piece"}],
         "steps": ["Cook the dal.", "Temper with ghee and hing."],
         "declaredTags": ["milk", "wheat", "gluten", "onion"],
         "provenance": {"source": "OffMyPlate team (original)", "notes": "Test fixture"},
         "review": {"status": "draft"}},
        {"id": "peanut-salad", "title": "Peanut salad", "region": "westIndian", "mealTypes": ["breakfast", "snack"], "lunchboxSuitable": true, "servings": 2, "prepMinutes": 10, "cookMinutes": 0,
         "ingredients": [{"ingredientId": "peanuts", "quantity": 100, "unit": "g"}, {"ingredientId": "onion", "quantity": 0.5, "unit": "piece"}],
         "steps": ["Mix everything."],
         "declaredTags": ["peanut", "onion"],
         "provenance": {"source": "Owner (adapted)"},
         "review": {"status": "signedOff", "reviewer": "Owner", "reviewedOn": "2026-10-12"}}
        ]}
        """

    static func files(
        catalog: String = SeedFixture.catalog, ingredients: String = SeedFixture.ingredients,
        recipes: String = SeedFixture.recipes
    ) -> SeedFiles {
        SeedFiles(catalog: Data(catalog.utf8), ingredients: Data(ingredients.utf8), recipes: Data(recipes.utf8))
    }

    /// `json` with every `target` replaced. Fails the test if `target` is absent, so a fixture
    /// edit can never turn a defect test into a silent no-op.
    static func mutated(_ json: String, replacing target: String, with replacement: String) throws -> String {
        try #require(json.contains(target), "fixture does not contain \(target)")
        return json.replacingOccurrences(of: target, with: replacement)
    }
}
