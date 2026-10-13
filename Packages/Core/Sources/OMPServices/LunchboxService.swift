import Foundation
import OMPDomain

/// The result of setting up school lunches (AC-7.2).
public struct LunchboxSetupResult: Sendable, Hashable {
    public let household: Household
    /// Working plans that gained (or lost) lunchbox meals: a draft edited in place, or a new
    /// draft revision of an approved plan (AC-5.4).
    public let updatedPlans: [ValidatedPlan]
    /// Set when the gate refused, so no plan was changed (the household change is saved).
    public let planningRefusal: GateRefusal?

    public init(household: Household, updatedPlans: [ValidatedPlan], planningRefusal: GateRefusal?) {
        self.household = household
        self.updatedPlans = updatedPlans
        self.planningRefusal = planningRefusal
    }
}

/// The lunchbox prompt and school-lunch setup (AC-7.1 to AC-7.3, U11, R7; task T18).
public final class LunchboxService: Sendable {
    let engine: PlanningEngine

    public init(context: ServiceContext) {
        self.engine = PlanningEngine(context: context)
    }

    var context: ServiceContext { engine.context }

    /// Whether `member` counts as one of "the kids" for the lunchbox prompt: created as a child,
    /// or with a child or teen age band (ASSUMPTION: teens may take lunch to school too).
    public static func isSchoolAge(_ member: Member) -> Bool {
        switch member.ageBand {
        case .some(.child), .some(.teen): return true
        case .some(.infant), .some(.toddler), .some(.adult), .some(.senior): return false
        case .none: return member.label.role == .child
        }
    }

    /// AC-7.1: called when the user opens a meal in `slot`. Returns the lunchbox card when the
    /// slot is a lunch, the household has a school-age member, and the prompt scheduler allows
    /// it now (AC-7.3 cooldown, AC-7.4 caps); the card is then recorded as shown.
    public func promptForOpenedSlot(_ slot: MealSlot) async throws -> PromptCandidate? {
        guard slot == .lunch || slot == .lunchbox else { return nil }
        return try await context.serialized {
            guard let household = try await context.repositories.household.fetch(),
                household.activeMembers.contains(where: LunchboxService.isSchoolAge)
            else { return nil }
            let now = context.clock.now
            let states = try await context.repositories.promptStates.fetchAll()
            let next = PromptScheduler.next(
                candidates: [.lunchbox], states: states, now: now, timeZone: context.clock.timeZone)
            guard let next, next.id == PromptScheduler.lunchboxPromptID else { return nil }
            let state = states.first { $0.promptId == next.id } ?? PromptState(promptId: next.id)
            try await context.repositories.promptStates.save(PromptScheduler.markShown(state, now: now))
            return next
        }
    }

    /// Records the answer on the lunchbox card (U11): Yes and No are final answers (never asked
    /// again; editable in Household); Not now starts the 14-day cooldown (AC-7.3).
    public func answerPrompt(_ answer: LunchboxPromptAnswer) async throws {
        try await context.serialized {
            let id = PromptScheduler.lunchboxPromptID
            let state = try await context.repositories.promptStates.fetch(id: id) ?? PromptState(promptId: id)
            let updated = PromptScheduler.recordLunchbox(answer, on: state, now: context.clock.now)
            try await context.repositories.promptStates.save(updated)
        }
    }

    /// AC-7.2: `children` take lunch to school on `days` (default Monday to Friday); every other
    /// member does not. Saves the household, then gives each working plan that still has days
    /// from today on a `lunchbox` meal on those days, filled only from lunchbox-suitable recipes,
    /// with those children not eating the family lunch that day (R7). Days already past and
    /// cooked meals are not changed. An approved plan gets a draft revision (AC-5.4).
    ///
    /// - Throws: `.safetyTransition(.unknownMember / .deletedMember)` for an id that is not an
    ///   active member.
    public func setUpSchoolLunches(children: [MemberID], days: Set<Weekday> = Weekday.schoolWeek) async throws
        -> LunchboxSetupResult
    {
        try await context.serialized {
            var household = try await engine.requireHousehold()
            let now = context.clock.now
            let chosen = Set(children)
            for id in chosen {
                guard let member = household.member(id) else {
                    throw ServiceError.safetyTransition(.unknownMember(id))
                }
                guard !member.isDeleted else { throw ServiceError.safetyTransition(.deletedMember(id)) }
            }
            for index in household.members.indices where !household.members[index].isDeleted {
                let takesLunch = chosen.contains(household.members[index].id) && !days.isEmpty
                household.members[index].needsSchoolLunch = takesLunch
                household.members[index].schoolDays = takesLunch ? days : []
            }
            household.updatedAt = now
            try await context.repositories.household.replace(with: household)

            let clearance: SafetyClearance
            switch SafetyGate.evaluate(household, now: now, timeZone: engine.timeZone) {
            case .success(let cleared):
                clearance = cleared
            case .failure(let refusal):
                return LunchboxSetupResult(household: household, updatedPlans: [], planningRefusal: refusal)
            }

            let today = LocalDate(now, in: engine.timeZone)
            let all = try await context.repositories.mealPlans.fetchAll()
            var seriesIDs: [PlanSeriesID] = []
            var seen = Set<PlanSeriesID>()
            for plan in all where seen.insert(plan.seriesId).inserted {
                seriesIDs.append(plan.seriesId)
            }
            let signals = try await engine.signals(now: now)

            var updated: [ValidatedPlan] = []
            for series in seriesIDs {
                guard let working = PlanningEngine.workingPlan(in: all, series: series), working.endDate >= today else {
                    continue
                }
                let arranged = arrangeLunchboxes(in: working, clearance: clearance, today: today)
                guard arranged.plan.meals != working.meals else { continue }
                let filled = try engine.replanMeals(
                    arranged.toFill, in: arranged.plan, household: household, clearance: clearance,
                    signals: signals, now: now)
                let revisionID = engine.newPlanID()
                let meals = filled.meals
                let edited = try mappingDomainErrors {
                    try PlanLifecycle.edit(working, newRevisionId: revisionID, now: now) { $0 = meals }
                }
                let fixed = try await engine.fixedDraft(edited, household: household, clearance: clearance, now: now)
                try await context.repositories.mealPlans.save(fixed.plan)
                updated.append(fixed)
            }
            return LunchboxSetupResult(household: household, updatedPlans: updated, planningRefusal: nil)
        }
    }

    // MARK: Private

    /// The plan with lunchbox meals arranged for the cleared members' school days, and the new
    /// (empty) lunchbox meals that still need a recipe.
    struct Arrangement {
        var plan: MealPlan
        var toFill: [PlannedMealID]
    }

    /// For each day from `today` on: adds or updates the lunchbox meal so exactly that day's
    /// school-lunch members eat it, marks them not eating at the family lunch (R7), and gives
    /// members who no longer take a lunchbox their family-lunch serving back. Cooked meals are
    /// left alone.
    func arrangeLunchboxes(in plan: MealPlan, clearance: SafetyClearance, today: LocalDate) -> Arrangement {
        var meals = plan.meals
        var toFill: [PlannedMealID] = []
        let usedIDs = Set(meals.map(\.id))

        for date in plan.dates where date >= today {
            let kids = Set(clearance.members.filter { SlotExpansion.needsLunchbox($0, on: date) }.map(\.id))
            let lunchboxIndex = meals.firstIndex { $0.date == date && $0.slot == .lunchbox }
            var formerKids = Set<MemberID>()
            if let index = lunchboxIndex {
                guard meals[index].cooked == nil else { continue }
                formerKids = Set(meals[index].eaterIDs)
            }

            if kids.isEmpty {
                if let index = lunchboxIndex {
                    meals.remove(at: index)
                }
            } else {
                let servings = clearance.members.map { member in
                    MealServing(memberId: member.id, portion: member.defaultPortion, notEating: !kids.contains(member.id))
                }
                if let index = lunchboxIndex {
                    if formerKids != kids {
                        meals[index].servings = servings
                    }
                } else {
                    var id = PlannedMealID(plan.id.rawValue + ":" + date.isoString + ":" + MealSlot.lunchbox.rawValue)
                    var suffix = 2
                    while usedIDs.contains(id) {
                        id = PlannedMealID(
                            plan.id.rawValue + ":" + date.isoString + ":" + MealSlot.lunchbox.rawValue + "#" + String(suffix))
                        suffix += 1
                    }
                    meals.append(
                        PlannedMeal(
                            id: id, date: date, slot: .lunchbox, recipeId: nil, emptyReason: .noSafeRecipe,
                            servings: servings))
                    toFill.append(id)
                }
            }

            // Family lunch (R7): today's lunchbox members do not eat it; former ones do again.
            if let lunch = meals.firstIndex(where: { $0.date == date && $0.slot == .lunch }), meals[lunch].cooked == nil {
                for serving in meals[lunch].servings.indices {
                    let member = meals[lunch].servings[serving].memberId
                    if kids.contains(member) {
                        meals[lunch].servings[serving].notEating = true
                    } else if formerKids.contains(member) {
                        meals[lunch].servings[serving].notEating = false
                    }
                }
            }
        }

        let order = SlotExpansion.fillOrder
        let sorted = meals.enumerated().sorted { lhs, rhs in
            let a = lhs.element
            let b = rhs.element
            if a.date != b.date { return a.date < b.date }
            let ra = order.firstIndex(of: a.slot) ?? order.count
            let rb = order.firstIndex(of: b.slot) ?? order.count
            if ra != rb { return ra < rb }
            return lhs.offset < rhs.offset
        }.map(\.element)

        var arranged = plan
        arranged.meals = sorted
        return Arrangement(plan: arranged, toFill: toFill)
    }
}
