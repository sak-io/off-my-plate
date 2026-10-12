import Foundation
import OMPDomain
import OMPRecipes
import Testing

@Suite("Seed review sheet")
struct ReviewSheetTests {
    @Test("golden output for the fixture library")
    func golden() throws {
        let library = try SeedLoader.load(SeedFixture.files())
        let sheet = SeedReviewSheet.markdown(for: library)
        #expect(sheet == Self.expected)
        if sheet != Self.expected {
            // Line-level hint for CI logs; the #expect above already failed.
            let got = sheet.split(separator: "\n", omittingEmptySubsequences: false)
            let want = Self.expected.split(separator: "\n", omittingEmptySubsequences: false)
            for (index, pair) in zip(got, want).enumerated() where pair.0 != pair.1 {
                Issue.record("first difference at line \(index + 1):\n got: \(pair.0)\nwant: \(pair.1)")
                break
            }
        }
    }

    @Test("the bundled library renders a sheet with one section per recipe")
    func bundled() throws {
        let library = try SeedLoader.loadBundled()
        let sheet = SeedReviewSheet.markdown(for: library)
        #expect(sheet.hasPrefix("# OffMyPlate seed review sheet\n"))
        for recipe in library.recipes {
            #expect(sheet.contains("### \(recipe.title) (`\(recipe.id)`)"))
        }
        #expect(sheet.contains("| `jain` | egg, fish, shellfish, beef, pork, poultry, otherMeat, gelatin, rootVegetable, onion, garlic, mushroom |"))
        #expect(sheet.contains("| nuts | `peanuts`, `tree-nuts` |"))
    }

    static let expected = """
        # OffMyPlate seed review sheet

        Content version: fixture-1 (schema 1)
        Recipes: 2 (signed off: 1, draft: 1)
        Ingredients: 5 (unverified: 1)

        "May contain" tags count as "contains" in every safety check. A recipe with an unverified ingredient is never planned for anyone who has a hard rule.

        ## Restrictions

        | Restriction | Excludes |
        |---|---|
        | `peanuts` | peanut |
        | `jain` | egg, rootVegetable, onion, garlic, mushroom |

        ## Keywords

        | Keyword | Selects |
        |---|---|
        | groundnut | `peanuts` |
        | nuts | `peanuts` |

        ## Recipes

        ### Dal tadka (`dal-tadka`)

        - Region: `northIndian`; meals: lunch, dinner; lunchbox: no; serves 4; 10 + 25 min
        - Provenance: OffMyPlate team (original) (Test fixture)
        - Review: draft
        - Derived tags: milk, wheat, gluten, onion
        - Unverified ingredients: `hing`

        | Ingredient | Amount | Contains | May contain | Status |
        |---|---|---|---|---|
        | Toor dal (`toor-dal`) | 150 g | none | none | verified |
        | Ghee (`ghee`) | 1 tbsp | milk | none | verified |
        | Asafoetida (`hing`) | a pinch (optional) | none | wheat, gluten | unverified |
        | Onion (`onion`) | 1 piece | onion | none | verified |

        - [ ] Ingredients and tags checked. Reviewer: ________ Date: ________

        ### Peanut salad (`peanut-salad`)

        - Region: `westIndian`; meals: breakfast, snack; lunchbox: yes; serves 2; 10 + 0 min
        - Provenance: Owner (adapted)
        - Review: signedOff by Owner on 2026-10-12
        - Derived tags: peanut, onion
        - Unverified ingredients: none

        | Ingredient | Amount | Contains | May contain | Status |
        |---|---|---|---|---|
        | Peanuts (`peanuts`) | 100 g | peanut | none | verified |
        | Onion (`onion`) | 0.5 piece | onion | none | verified |

        - [ ] Ingredients and tags checked. Reviewer: ________ Date: ________

        """
}
