import Foundation
import OMPDomain
import OMPServices

@testable import OMPData

/// 2026-10-12T00:00:00Z.
let fixtureNow = Date(timeIntervalSince1970: 1_791_763_200)
let fixtureMonday = LocalDate(year: 2026, month: 10, day: 12)!

/// The two store kinds every repository contract case runs against (task T20).
enum StoreKind: String, CaseIterable, Sendable {
    case inMemory
    case onDisk
}

/// A store for one test: in memory, or on disk in its own temporary directory.
struct TestStore: Sendable {
    let store: PersistenceStore
    let directory: URL?

    static func make(_ kind: StoreKind) throws -> TestStore {
        switch kind {
        case .inMemory:
            return TestStore(store: try PersistenceStore(location: .inMemory), directory: nil)
        case .onDisk:
            let directory = temporaryDirectory()
            return TestStore(store: try PersistenceStore(location: .directory(directory)), directory: directory)
        }
    }

    /// A fresh, not yet existing directory under the system temporary directory.
    static func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("omp-data-tests-\(UUID().uuidString)", isDirectory: true)
    }

    func cleanUp() {
        if let directory {
            try? FileManager.default.removeItem(at: directory)
        }
    }
}

func fixturePlan(
    _ id: MealPlanID, series: PlanSeriesID, revision: Int, status: PlanStatus = .draft, meals: [PlannedMeal] = []
) -> MealPlan {
    MealPlan(
        id: id, seriesId: series, revision: revision, weekStart: fixtureMonday, status: status, meals: meals,
        contentVersion: "seed-1", createdAt: fixtureNow)
}

func fixturePantryItem(_ id: PantryItemID, quantity: Double) -> PantryItem {
    PantryItem(
        id: id, item: .ingredient("rice"), quantity: quantity, unit: .kilogram, location: .shelf,
        lastConfirmedAt: fixtureNow, source: .manual)
}

/// A household that uses every member and rule field, including a soft-deleted member.
func richHousehold() -> Household {
    let adult = Member(
        id: "a1", label: MemberLabel(role: .adult, number: 1), name: "Asha", ageBand: .adult,
        safetyStatus: .stated, safetyConfirmedAt: fixtureNow.addingTimeInterval(-3_600))
    let child = Member(
        id: "c1", label: MemberLabel(role: .child, number: 1), ageBand: .child, safetyStatus: .confirmedNone,
        safetyConfirmedAt: fixtureNow, needsSchoolLunch: true, schoolDays: [.monday, .wednesday, .friday],
        portionOverride: 0.75)
    let removed = Member(
        id: "a2", label: MemberLabel(role: .adult, number: 2), safetyStatus: .unasked,
        deletedAt: fixtureNow.addingTimeInterval(0.123_456))
    let peanut = Rule(
        id: "r1", scope: .member("a1"), restriction: "peanut", excludedTags: [.peanut, .treeNut],
        createdAt: fixtureNow)
    let jain = Rule(
        id: "r2", scope: .household, restriction: "jain",
        excludedTags: [.rootVegetable, .onion, .garlic, .mushroom], createdAt: fixtureNow.addingTimeInterval(1))
    return Household(
        id: "h", members: [child, adult, removed], rules: [jain, peanut],
        settings: HouseholdSettings(snacksEnabled: true, weekStartsOn: .sunday),
        createdAt: fixtureNow, updatedAt: fixtureNow.addingTimeInterval(60))
}

/// Two meals that use every `PlannedMeal` field and every `ExplanationReason` case.
func richMeals() -> [PlannedMeal] {
    [
        PlannedMeal(
            id: "m1", date: fixtureMonday, slot: .dinner, recipeId: "dal-tadka", locked: true,
            servings: [MealServing(memberId: "a1", portion: 1.0), MealServing(memberId: "c1", portion: 0.6)],
            reasons: [.usesYourIngredient("rice"), .quickWeekday(.dinner)],
            cooked: CookRef(cookLogId: "c1", cookedAt: Date(timeIntervalSinceReferenceDate: 813_456_000))),
        PlannedMeal(
            id: "m2", date: fixtureMonday.adding(days: 1), slot: .lunchbox, recipeId: nil,
            emptyReason: .noSafeRecipe,
            servings: [MealServing(memberId: "c1", portion: 0.6, notEating: true)],
            reasons: [
                .cuisineYouLike("southIndian"), .goodForLunchboxes, .differentFromYesterday, .cookedOften,
                .usesExpiringIngredient("curd"), .repeatedFewSafeOptions,
            ],
            blockedBySafety: true),
    ]
}

/// An approved plan with meals: approval columns and the content blob are both exercised.
func richApprovedPlan() -> MealPlan {
    MealPlan(
        id: "p1", seriesId: "s1", revision: 2, basedOn: "p0", weekStart: fixtureMonday, status: .approved,
        meals: richMeals(),
        approval: PlanApproval(approvedAt: fixtureNow.addingTimeInterval(0.5), contentHash: String(repeating: "ab", count: 32)),
        contentVersion: "seed-3", createdAt: fixtureNow)
}

/// One learning event of every kind.
func allLearningEvents() -> [LearningEvent] {
    [
        LearningEvent(id: "e1", kind: .swapped(from: "r1", to: "r2", slot: .dinner), at: fixtureNow),
        LearningEvent(id: "e2", kind: .rerolled(recipe: "r1", slot: .lunch, reason: .kidsWontEatIt), at: fixtureNow),
        LearningEvent(id: "e3", kind: .rerolled(recipe: "r1", slot: .lunch, reason: nil), at: fixtureNow),
        LearningEvent(id: "e4", kind: .skipped(recipe: "r3", slot: .breakfast), at: fixtureNow),
        LearningEvent(id: "e5", kind: .cooked(recipe: "r4"), at: fixtureNow),
        LearningEvent(id: "e6", kind: .importedItem(ingredient: "rice"), at: fixtureNow),
        LearningEvent(
            id: "e7",
            kind: .reflectBackAnswered(
                key: FactKey(subject: .member("c1"), statement: .dislikesIngredient("okra")), answer: .dontAskAgain),
            at: fixtureNow),
        LearningEvent(
            id: "e8",
            kind: .reflectBackAnswered(
                key: FactKey(subject: .household, statement: .prefersQuickWeekday), answer: .yes),
            at: fixtureNow),
    ]
}

/// One fact of every statement kind, both subjects.
func allFacts() -> [Fact] {
    let statements: [FactStatement] = [
        .cuisineAffinity("southIndian"), .dislikesRecipe("r1"), .dislikesIngredient("okra"), .prefersQuickWeekday,
        .staple("rice"), .favouriteRecipe("r2"),
    ]
    return statements.enumerated().map { index, statement in
        Fact(
            id: FactID("f\(index)"), subject: index.isMultiple(of: 2) ? .household : .member("c1"),
            statement: statement, origin: FactOrigin.allCases[index % FactOrigin.allCases.count],
            confidence: 0.25 * Double(index % 4), status: FactStatus.allCases[index % FactStatus.allCases.count],
            suppressed: index == 3, forgottenAt: index == 4 ? fixtureNow : nil, createdAt: fixtureNow,
            updatedAt: fixtureNow.addingTimeInterval(Double(index)))
    }
}
