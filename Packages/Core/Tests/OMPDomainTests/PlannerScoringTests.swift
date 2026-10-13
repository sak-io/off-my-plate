import Foundation
import OMPDomain
import Testing

private typealias P = PlannerFixture

/// Signals and scoring helpers for the T11 tests.
enum ScoringFixture {
    static func pantry(
        _ id: IngredientID, expires: LocalDate? = nil, location: StorageLocation = .shelf,
        confirmedDaysAgo: Int = 0, quantity: Double = 500
    ) -> PantryItem {
        PantryItem(
            id: PantryItemID("pantry-" + id.rawValue), item: .ingredient(id), quantity: quantity, unit: .gram,
            location: location, expiresOn: expires, lastConfirmedAt: P.now - Double(confirmedDaysAgo) * P.day,
            source: .manual)
    }

    static func fact(
        _ statement: FactStatement, origin: FactOrigin = .stated, confidence: Double = 1, status: FactStatus = .active,
        subject: FactSubject = .household
    ) -> Fact {
        Fact(
            id: FactID("fact-\(statement)-\(origin.rawValue)"), subject: subject, statement: statement, origin: origin,
            confidence: confidence, status: status, createdAt: P.now, updatedAt: P.now)
    }

    static func cooked(_ recipe: RecipeID, daysAgo: Int) -> CookLog {
        CookLog(
            id: CookLogID("cook-" + recipe.rawValue), planId: "old-plan", mealId: "old-meal", recipeId: recipe,
            cookedAt: P.now - Double(daysAgo) * P.day + 3_600)
    }

    static func context(_ signals: PlannerSignals = PlannerSignals()) -> PlannerScoring.Context {
        PlannerScoring.Context(signals: signals, now: P.now, timeZone: P.utc)
    }

    /// Scores `recipe` (from the fixture library unless `library` is given) for a meal both
    /// members eat.
    static func score(
        _ recipe: RecipeID, signals: PlannerSignals = PlannerSignals(), date: LocalDate = P.monday,
        slot: MealSlot = .dinner, eaters: [MemberID] = [P.adult, P.child], uses: [RecipeID: [LocalDate]] = [:],
        library: PlannerLibrary = P.library
    ) throws -> PlannerScoring.Breakdown {
        let entry = try #require(library.entry(recipe))
        return PlannerScoring.score(
            entry, date: date, slot: slot, eaterIDs: eaters, plannedUses: uses, context: context(signals))
    }
}

private typealias S = ScoringFixture

@Suite("PlannerScoring: each component in isolation (plan section 5 step 4)")
struct PlannerScoringComponentTests {
    @Test("no signals: only time fit, and only for weekday dinners within 40 minutes")
    func noSignals() throws {
        #expect(try S.score("d-veg-pulao").points == [.timeFit: 100])
        // 2026-10-17 is a Saturday.
        #expect(try S.score("d-veg-pulao", date: P.monday.adding(days: 5)).points == [:])
        #expect(try S.score("l-rajma", slot: .lunch).points == [:])
        var slow = P.recipe("d-slow", [.dinner], ["rice"])
        slow.cookMinutes = 31  // 41 minutes in total
        let library = P.makeLibrary([slow])
        #expect(try S.score("d-slow", library: library).points == [:])
        slow.cookMinutes = 30  // exactly 40 minutes
        #expect(try S.score("d-slow", library: P.makeLibrary([slow])).points == [.timeFit: 100])
    }

    @Test("pantry coverage: +3 times the covered fraction of required ingredients")
    func pantryCoverage() throws {
        let half = PlannerSignals(pantry: [S.pantry("rice")])
        #expect(try S.score("d-veg-pulao", signals: half).points[.pantryCoverage] == 150)
        let full = PlannerSignals(pantry: [S.pantry("rice"), S.pantry("vegetables")])
        #expect(try S.score("d-veg-pulao", signals: full).points[.pantryCoverage] == 300)
        // Optional lines do not count (hing is optional in dal tadka).
        let hing = PlannerSignals(pantry: [S.pantry("hing")])
        #expect(try S.score("d-dal-tadka", signals: hing).points[.pantryCoverage] == nil)
    }

    @Test("pantry coverage ignores low-confidence, expired, empty and unresolved items")
    func pantryCoverageIgnoresUnusable() throws {
        let unusable: [PantryItem] = [
            S.pantry("rice", location: .fridge, confirmedDaysAgo: 8),
            S.pantry("vegetables", expires: P.monday.adding(days: -1)),
            S.pantry("rice", quantity: 0),
            PantryItem(
                id: "free", item: .freeText("rice"), quantity: 1, unit: .kilogram, location: .shelf,
                lastConfirmedAt: P.now, source: .manual),
        ]
        #expect(try S.score("d-veg-pulao", signals: PlannerSignals(pantry: unusable)).points == [.timeFit: 100])
        // An item that is gone by the meal's date does not cover that meal.
        let shortLived = PlannerSignals(pantry: [S.pantry("rice", expires: P.monday.adding(days: 1))])
        let wednesday = P.monday.adding(days: 2)
        #expect(try S.score("d-veg-pulao", signals: shortLived, date: wednesday).points == [.timeFit: 100])
    }

    @Test("expiry soon: +2 when a required ingredient expires within 3 days and is in date for the meal")
    func expirySoon() throws {
        let soon = PlannerSignals(pantry: [S.pantry("rice", expires: P.monday.adding(days: 3))])
        let breakdown = try S.score("d-veg-pulao", signals: soon)
        #expect(breakdown.points[.expirySoon] == 200)
        #expect(breakdown.points[.pantryCoverage] == 150)
        let later = PlannerSignals(pantry: [S.pantry("rice", expires: P.monday.adding(days: 4))])
        #expect(try S.score("d-veg-pulao", signals: later).points[.expirySoon] == nil)
        // On a day after the item expired neither expiry nor coverage applies.
        #expect(try S.score("d-veg-pulao", signals: soon, date: P.monday.adding(days: 4)).points[.expirySoon] == nil)
    }

    @Test("cuisine affinity: +2 times confidence, only for active stated or confirmed Facts (AC-12.6)")
    func cuisineAffinity() throws {
        let stated = PlannerSignals(facts: [S.fact(.cuisineAffinity("southIndian"))])
        #expect(try S.score("d-veg-pulao", signals: stated).points[.cuisineAffinity] == 200)
        let confirmed = PlannerSignals(
            facts: [S.fact(.cuisineAffinity("southIndian"), origin: .confirmed, confidence: 0.5)])
        #expect(try S.score("d-veg-pulao", signals: confirmed).points[.cuisineAffinity] == 100)
        let ignored: [Fact] = [
            S.fact(.cuisineAffinity("southIndian"), origin: .inferred, confidence: 0.9),
            S.fact(.cuisineAffinity("southIndian"), origin: .appDefault),
            S.fact(.cuisineAffinity("southIndian"), status: .proposed),
            S.fact(.cuisineAffinity("southIndian"), status: .dismissed),
            S.fact(.cuisineAffinity("northIndian")),
            S.fact(.cuisineAffinity("southIndian"), confidence: .nan),
        ]
        #expect(try S.score("d-veg-pulao", signals: PlannerSignals(facts: ignored)).points == [.timeFit: 100])
    }

    @Test("favourite +1 and disliked recipe -4")
    func favouriteAndDislike() throws {
        let favourite = PlannerSignals(facts: [S.fact(.favouriteRecipe("d-veg-pulao"))])
        #expect(try S.score("d-veg-pulao", signals: favourite).points[.favourite] == 100)
        #expect(try S.score("d-egg-curry", signals: favourite).points[.favourite] == nil)
        let disliked = PlannerSignals(facts: [S.fact(.dislikesRecipe("d-veg-pulao"))])
        #expect(try S.score("d-veg-pulao", signals: disliked).points[.dislikeRecipe] == -400)
    }

    @Test("disliked ingredient -2 per distinct required ingredient; optional lines are not counted")
    func dislikedIngredients() throws {
        let both = PlannerSignals(
            facts: [S.fact(.dislikesIngredient("rice")), S.fact(.dislikesIngredient("vegetables"))])
        #expect(try S.score("d-veg-pulao", signals: both).points[.dislikeIngredient] == -400)
        let optional = PlannerSignals(facts: [S.fact(.dislikesIngredient("hing"))])
        #expect(try S.score("d-dal-tadka", signals: optional).points[.dislikeIngredient] == nil)
    }

    @Test("member Facts apply only when that member is eating")
    func memberFacts() throws {
        let childDislike = PlannerSignals(facts: [S.fact(.dislikesRecipe("d-veg-pulao"), subject: .member(P.child))])
        #expect(try S.score("d-veg-pulao", signals: childDislike).points[.dislikeRecipe] == -400)
        #expect(try S.score("d-veg-pulao", signals: childDislike, eaters: [P.adult]).points[.dislikeRecipe] == nil)
    }

    @Test("a stated quick-weekday preference adds to time fit (assumption)")
    func prefersQuickWeekday() throws {
        let quick = PlannerSignals(facts: [S.fact(.prefersQuickWeekday)])
        #expect(try S.score("d-veg-pulao", signals: quick).points[.timeFit] == 200)
        #expect(try S.score("d-veg-pulao", signals: quick, date: P.monday.adding(days: 6)).points[.timeFit] == nil)
    }

    @Test("recently cooked -2 within 7 days before the meal")
    func recentlyCooked() throws {
        let recent = PlannerSignals(cookLog: [S.cooked("d-veg-pulao", daysAgo: 3)])
        #expect(try S.score("d-veg-pulao", signals: recent).points[.recentlyCooked] == -200)
        let old = PlannerSignals(cookLog: [S.cooked("d-veg-pulao", daysAgo: 8)])
        #expect(try S.score("d-veg-pulao", signals: old).points[.recentlyCooked] == nil)
        // 7 days before the meal still counts; 8 does not.
        let sunday = P.monday.adding(days: -1)
        #expect(try S.score("d-veg-pulao", signals: old, date: sunday).points[.recentlyCooked] == -200)
    }

    @Test("same-day duplicate -3")
    func sameDayDuplicate() throws {
        #expect(try S.score("d-veg-pulao", uses: ["d-veg-pulao": [P.monday]]).points[.sameDayDuplicate] == -300)
        let tuesday = P.monday.adding(days: 1)
        #expect(try S.score("d-veg-pulao", uses: ["d-veg-pulao": [tuesday]]).points[.sameDayDuplicate] == nil)
    }
}

@Suite("PlannerScoring: explanations (AC-4.7, plan section 5 step 7)")
struct PlannerExplanationTests {
    @Test("top two positive components by points; ties follow the component order")
    func topTwo() throws {
        let signals = PlannerSignals(
            pantry: [S.pantry("rice"), S.pantry("vegetables")],
            facts: [
                S.fact(.cuisineAffinity("southIndian"), origin: .confirmed, confidence: 0.5),
                S.fact(.favouriteRecipe("d-veg-pulao")),
            ])
        let breakdown = try S.score("d-veg-pulao", signals: signals)
        // coverage 300 > cuisine 100 = favourite 100 = time fit 100.
        #expect(breakdown.reasons == [.usesYourIngredient("rice"), .cuisineYouLike("southIndian")])
        #expect(breakdown.total == 600)
    }

    @Test("an expiring ingredient is named once; coverage names another covered ingredient")
    func expiringNamedOnce() throws {
        let onlyRice = PlannerSignals(pantry: [S.pantry("rice", expires: P.monday.adding(days: 1))])
        let expected: [ExplanationReason] = [.usesExpiringIngredient("rice"), .quickWeekday(.dinner)]
        #expect(try S.score("d-veg-pulao", signals: onlyRice).reasons == expected)
        let both = PlannerSignals(pantry: [S.pantry("rice", expires: P.monday.adding(days: 1)), S.pantry("vegetables")])
        let named: [ExplanationReason] = [.usesYourIngredient("vegetables"), .usesExpiringIngredient("rice")]
        #expect(try S.score("d-veg-pulao", signals: both).reasons == named)
    }

    @Test("negative components never explain; fillers complete the explanation")
    func fillers() throws {
        let disliked = PlannerSignals(facts: [S.fact(.dislikesRecipe("x-lemon-rice"))])
        let lunchbox = try S.score("x-lemon-rice", signals: disliked, slot: .lunchbox, eaters: [P.child])
        #expect(lunchbox.reasons == [.goodForLunchboxes, .differentFromYesterday])
        let yesterday = try S.score(
            "x-lemon-rice", slot: .lunchbox, eaters: [P.child], uses: ["x-lemon-rice": [P.monday.adding(days: -1)]])
        #expect(yesterday.reasons == [.goodForLunchboxes])
        #expect(try S.score("l-rajma", slot: .lunch).reasons == [.differentFromYesterday])
    }

    @Test("every planned meal has an explanation")
    func everyMealExplained() throws {
        let plan = try P.generate(P.household(snacks: true, lunchbox: true))
        for meal in plan.meals {
            #expect(!meal.reasons.isEmpty, "\(meal.id)")
            #expect(meal.reasons.count <= 2)
        }
    }
}

@Suite("WeekPlanner with signals (AC-4.6, AC-12.6)")
struct PlannerSignalsTests {
    @Test("pantry and expiry pull a recipe into the earliest slot")
    func pantryPreferred() throws {
        let household = P.household()
        let signals = PlannerSignals(pantry: [S.pantry("rajma", expires: P.monday.adding(days: 1))])
        let plan = try WeekPlanner.generateWeek(
            clearance: P.clearance(household), household: household, library: P.library, request: P.request(),
            signals: signals, now: P.now, timeZone: P.utc)
        let lunches = P.meals(plan, .lunch)
        #expect(lunches[0].recipeId == "l-rajma")
        #expect(lunches[0].reasons.first == .usesExpiringIngredient("rajma"))
    }

    @Test("a disliked recipe is avoided while others exist, but used when it is the only safe one")
    func dislikeOnlyScores() throws {
        let household = P.household()
        let signals = PlannerSignals(facts: [S.fact(.dislikesRecipe("d-veg-pulao"))])
        let plan = try WeekPlanner.generateWeek(
            clearance: P.clearance(household), household: household, library: P.library, request: P.request(),
            signals: signals, now: P.now, timeZone: P.utc)
        #expect(P.meals(plan, .dinner).prefix(3).allSatisfy { $0.recipeId != "d-veg-pulao" })

        let only = P.makeLibrary([P.recipe("d-veg-pulao", [.dinner], ["rice", "vegetables"])])
        let forced = try WeekPlanner.generateWeek(
            clearance: P.clearance(household), household: household, library: only, request: P.request(),
            signals: signals, now: P.now, timeZone: P.utc)
        #expect(P.meals(forced, .dinner).allSatisfy { $0.recipeId == "d-veg-pulao" })
    }

    @Test("AC-12.6: Facts never make an unsafe recipe plannable; the hard-filter output is unchanged")
    func factsNeverAffectSafety() throws {
        let household = P.household(
            rules: [P.rule("peanuts", .member(P.child), [.peanut]), P.rule("egg", .household, [.egg])], snacks: true)
        let clearance = try P.clearance(household)
        // Every Fact the planner can use, pointing at the unsafe recipes.
        var facts: [Fact] = []
        for id in ["b-poha", "d-egg-curry", "s-masala-chana"] as [RecipeID] {
            facts.append(S.fact(.favouriteRecipe(id)))
        }
        facts.append(S.fact(.cuisineAffinity("southIndian")))
        let disliked: [IngredientID] = ["rice", "vegetables", "toor-dal", "atta"]
        facts += disliked.map { S.fact(.dislikesIngredient($0)) }
        let signals = PlannerSignals(
            pantry: [S.pantry("peanuts", expires: P.monday), S.pantry("egg", expires: P.monday)], facts: facts)

        for seed in UInt64(0)..<10 {
            let request = P.request(seed: PlannerSeed(seed))
            let plain = try WeekPlanner.generateWeek(
                clearance: clearance, household: household, library: P.library, request: request, now: P.now,
                timeZone: P.utc)
            let scored = try WeekPlanner.generateWeek(
                clearance: clearance, household: household, library: P.library, request: request, signals: signals,
                now: P.now, timeZone: P.utc)
            #expect(plain.meals.map { $0.recipeId == nil } == scored.meals.map { $0.recipeId == nil })
            for meal in scored.meals {
                let allowed = HardFilter.candidates(
                    for: meal.slot, eaterIDs: meal.eaterIDs, library: P.library, clearance: clearance
                ).map(\.id)
                if let id = meal.recipeId {
                    #expect(allowed.contains(id), "\(meal.id) \(id)")
                }
            }
        }
    }

    @Test("AC-4.6: the same inputs, signals and seed give an identical plan")
    func deterministicWithSignals() throws {
        let household = P.household(snacks: true, lunchbox: true)
        let signals = PlannerSignals(
            pantry: [S.pantry("rice", expires: P.monday.adding(days: 2)), S.pantry("chana")],
            facts: [S.fact(.cuisineAffinity("southIndian"), origin: .confirmed, confidence: 0.7)],
            cookLog: [S.cooked("d-veg-pulao", daysAgo: 1)])
        let generate = {
            try WeekPlanner.generateWeek(
                clearance: P.clearance(household), household: household, library: P.library, request: P.request(),
                signals: signals, now: P.now, timeZone: P.utc)
        }
        #expect(try generate() == generate())
    }

    @Test("performance: a week with a large library and signals plans well within budget")
    func performanceBudget() throws {
        var recipes: [Recipe] = []
        let pool: [IngredientID] = ["rice", "toor-dal", "vegetables", "atta", "chana", "banana", "lemon", "curd"]
        for index in 0..<200 {
            let lines = (0..<4).map { pool[(index + $0 * 3) % pool.count] }
            let types: Set<MealType> = [MealType.allCases[index % 4], MealType.allCases[(index + 1) % 4]]
            recipes.append(P.recipe(RecipeID("r-\(index)"), types, lines, lunchbox: index % 5 == 0))
        }
        let library = P.makeLibrary(recipes)
        let signals = PlannerSignals(
            pantry: pool.map { S.pantry($0, expires: P.monday.adding(days: 2)) },
            facts: (0..<30).map { S.fact(.favouriteRecipe(RecipeID("r-\($0 * 7)"))) },
            cookLog: (0..<30).map { S.cooked(RecipeID("r-\($0 * 11)"), daysAgo: $0 % 10) })
        let household = P.household(rules: [P.rule("milk", .member(P.child), [.milk])], snacks: true, lunchbox: true)
        let clearance = try P.clearance(household)
        let run = {
            _ = try WeekPlanner.generateWeek(
                clearance: clearance, household: household, library: library, request: P.request(), signals: signals,
                now: P.now, timeZone: P.utc)
        }
        try run()  // warm-up
        let elapsed = try ContinuousClock().measure { try run() }
        // The product budget is 200 ms per week (T11); CI debug builds on shared runners are
        // noisy, so the assertion only catches gross regressions (T11 review-1).
        #expect(elapsed < .seconds(2), "\(elapsed)")
    }
}
