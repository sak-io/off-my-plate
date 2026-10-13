import Foundation

/// The soft inputs the planner scores with (plan section 5 step 1): the pantry snapshot, the
/// household's Facts and the cook log. None of them can make a recipe plannable or unplannable;
/// they only change scores (AC-12.6). Safety comes only from the `SafetyClearance`.
public struct PlannerSignals: Sendable, Hashable {
    public var pantry: [PantryItem]
    public var facts: [Fact]
    /// Recent cooking (the caller passes at least the last 14 days; older entries are ignored).
    public var cookLog: [CookLog]

    public init(pantry: [PantryItem] = [], facts: [Fact] = [], cookLog: [CookLog] = []) {
        self.pantry = pantry
        self.facts = facts
        self.cookLog = cookLog
    }
}

/// One score component (plan section 5 step 4).
public enum ScoreComponent: String, CaseIterable, Codable, Sendable, Hashable {
    case pantryCoverage
    case expirySoon
    case cuisineAffinity
    case favourite
    case dislikeRecipe
    case dislikeIngredient
    case timeFit
    case recentlyCooked
    case sameDayDuplicate
}

/// Fixed-weight scoring and explanations (plan section 5 steps 4 and 7; AC-4.7, AC-12.6).
///
/// Scores are integer **points** (hundredths of the plan's weights, so `+3` is 300), which keeps
/// comparisons and ties exact and identical on every platform.
public enum PlannerScoring {
    // MARK: Weights (plan section 5 step 4), in points

    /// Times the fraction of required ingredients covered by the pantry.
    public static let pantryCoverageWeight = 300
    public static let expirySoonWeight = 200
    /// Times the Fact's confidence (0...1).
    public static let cuisineAffinityWeight = 200
    public static let favouriteWeight = 100
    public static let dislikeRecipeWeight = -400
    /// Per distinct disliked required ingredient.
    public static let dislikeIngredientWeight = -200
    /// Weekday dinner within `quickWeekdayMaxMinutes`.
    public static let timeFitWeight = 100
    /// ASSUMPTION (T11 handoff): an active `prefersQuickWeekday` Fact adds this to `timeFit`.
    public static let prefersQuickWeekdayBonus = 100
    public static let recentlyCookedWeight = -200
    public static let sameDayDuplicateWeight = -300

    // MARK: Thresholds

    /// A pantry item "expires soon" when its best-before day is at most this many days after today.
    public static let expirySoonDays = 3
    /// A recipe cooked up to this many days before the meal's date counts as recently cooked.
    public static let recentlyCookedDays = 7
    public static let quickWeekdayMaxMinutes = 40
    /// The days on which "quick weekday" applies (Monday to Friday).
    public static let weekdays: Set<Weekday> = [.monday, .tuesday, .wednesday, .thursday, .friday]

    /// The precomputed signals for one planning run.
    public struct Context: Sendable {
        /// Facts the planner may use: only `.active` Facts that were stated or confirmed
        /// (AC-12.6). Inferred and default Facts never score.
        struct UsableFact: Sendable {
            var subject: FactSubject
            var statement: FactStatement
            var confidence: Double
        }

        public let today: LocalDate
        /// Expiry days (nil = no expiry) of the confident, usable pantry items per ingredient.
        let pantryExpiries: [IngredientID: [LocalDate?]]
        let facts: [UsableFact]
        let cookedDays: [RecipeID: [LocalDate]]

        public init(signals: PlannerSignals, now: Date, timeZone: TimeZone) {
            let today = LocalDate(now, in: timeZone)
            self.today = today

            var pantry: [IngredientID: [LocalDate?]] = [:]
            for item in signals.pantry {
                guard let id = item.item.ingredientId, item.isUsableForRequirements(today: today),
                    item.confidence(now: now, timeZone: timeZone) == .confident
                else { continue }
                pantry[id, default: []].append(item.expiresOn)
            }
            self.pantryExpiries = pantry

            self.facts = signals.facts.compactMap { fact -> UsableFact? in
                guard fact.status == .active, fact.origin == .stated || fact.origin == .confirmed else { return nil }
                let confidence = fact.confidence.isNaN ? 0 : min(max(fact.confidence, 0), 1)
                return UsableFact(subject: fact.subject, statement: fact.statement, confidence: confidence)
            }

            var cooked: [RecipeID: [LocalDate]] = [:]
            for entry in signals.cookLog {
                cooked[entry.recipeId, default: []].append(LocalDate(entry.cookedAt, in: timeZone))
            }
            self.cookedDays = cooked
        }

        /// The usable Facts that apply to a meal eaten by `eaterIDs`: household Facts, and
        /// member Facts of members who are eating.
        func facts(for eaterIDs: [MemberID]) -> [UsableFact] {
            facts.filter { fact in
                switch fact.subject {
                case .household: return true
                case .member(let id): return eaterIDs.contains(id)
                }
            }
        }

        /// Whether a usable pantry item of `ingredient` is still in date on `date`.
        func pantryHas(_ ingredient: IngredientID, on date: LocalDate) -> Bool {
            guard let expiries = pantryExpiries[ingredient] else { return false }
            return expiries.contains { expiry in
                guard let expiry else { return true }
                return expiry >= date
            }
        }

        /// The earliest expiry of an in-date (on `date`) pantry item of `ingredient` that
        /// expires within `expirySoonDays` of today.
        func soonExpiry(_ ingredient: IngredientID, on date: LocalDate) -> LocalDate? {
            pantryExpiries[ingredient]?.compactMap { $0 }
                .filter { $0 >= date && $0.daysSince(today) <= PlannerScoring.expirySoonDays }
                .min()
        }
    }

    /// A recipe's score for one meal, by component, with its explanation.
    public struct Breakdown: Sendable, Hashable {
        /// Non-zero components only.
        public let points: [ScoreComponent: Int]
        /// Up to two reasons (plan section 5 step 7).
        public let reasons: [ExplanationReason]

        public var total: Int {
            points.values.reduce(0, +)
        }
    }

    /// Scores `entry` for the meal on `date` in `slot` eaten by `eaterIDs`.
    ///
    /// - Parameter plannedUses: the dates each recipe is already used on elsewhere in the plan.
    public static func score(
        _ entry: PlannerLibrary.Entry, date: LocalDate, slot: MealSlot, eaterIDs: [MemberID],
        plannedUses: [RecipeID: [LocalDate]], context: Context
    ) -> Breakdown {
        var points: [ScoreComponent: Int] = [:]
        // Positive components and their reason, in tie-break priority order.
        var positives: [(component: ScoreComponent, reason: ExplanationReason)] = []
        let required = entry.requiredIngredients

        // Expiry first: it is the more specific "uses your ..." reason.
        var expiring: (id: IngredientID, day: LocalDate)?
        for id in required {
            if let day = context.soonExpiry(id, on: date), expiring.map({ day < $0.day }) ?? true {
                expiring = (id, day)
            }
        }
        if let expiring {
            points[.expirySoon] = expirySoonWeight
            positives.append((.expirySoon, .usesExpiringIngredient(expiring.id)))
        }

        let covered = required.filter { context.pantryHas($0, on: date) }
        if !covered.isEmpty {
            points[.pantryCoverage] = pantryCoverageWeight * covered.count / required.count
            if let shown = covered.first(where: { $0 != expiring?.id }) {
                positives.append((.pantryCoverage, .usesYourIngredient(shown)))
            }
        }

        let facts = context.facts(for: eaterIDs)
        var cuisineConfidence = 0.0
        var favourite = false
        var dislikedRecipe = false
        var dislikedIngredients = Set<IngredientID>()
        var prefersQuick = false
        for fact in facts {
            switch fact.statement {
            case .cuisineAffinity(let cuisine) where cuisine == entry.region:
                cuisineConfidence = max(cuisineConfidence, fact.confidence)
            case .favouriteRecipe(let id) where id == entry.id:
                favourite = true
            case .dislikesRecipe(let id) where id == entry.id:
                dislikedRecipe = true
            case .dislikesIngredient(let id) where required.contains(id):
                dislikedIngredients.insert(id)
            case .prefersQuickWeekday:
                prefersQuick = true
            default:
                break
            }
        }
        let cuisinePoints = Int((Double(cuisineAffinityWeight) * cuisineConfidence).rounded())
        if cuisinePoints > 0 {
            points[.cuisineAffinity] = cuisinePoints
            positives.append((.cuisineAffinity, .cuisineYouLike(entry.region)))
        }
        if favourite {
            points[.favourite] = favouriteWeight
            positives.append((.favourite, .cookedOften))
        }
        if dislikedRecipe {
            points[.dislikeRecipe] = dislikeRecipeWeight
        }
        if !dislikedIngredients.isEmpty {
            points[.dislikeIngredient] = dislikeIngredientWeight * dislikedIngredients.count
        }

        if slot == .dinner, weekdays.contains(date.weekday), entry.totalMinutes <= quickWeekdayMaxMinutes {
            points[.timeFit] = timeFitWeight + (prefersQuick ? prefersQuickWeekdayBonus : 0)
            positives.append((.timeFit, .quickWeekday(slot)))
        }

        let cooked = context.cookedDays[entry.id] ?? []
        if cooked.contains(where: { (0...recentlyCookedDays).contains(date.daysSince($0)) }) {
            points[.recentlyCooked] = recentlyCookedWeight
        }
        let uses = plannedUses[entry.id] ?? []
        if uses.contains(date) {
            points[.sameDayDuplicate] = sameDayDuplicateWeight
        }

        // Top two positive components: by points, then by the order above (stable sort).
        var reasons = positives.enumerated()
            .sorted { lhs, rhs in
                let left = points[lhs.element.component] ?? 0
                let right = points[rhs.element.component] ?? 0
                return left != right ? left > right : lhs.offset < rhs.offset
            }
            .prefix(2)
            .map { $0.element.reason }
        // Fillers so every planned meal has an explanation (AC-4.7); they carry no points.
        if reasons.count < 2, slot == .lunchbox {
            reasons.append(.goodForLunchboxes)
        }
        let yesterday = date.adding(days: -1)
        if reasons.count < 2, !uses.contains(yesterday), !cooked.contains(yesterday) {
            reasons.append(.differentFromYesterday)
        }
        return Breakdown(points: points, reasons: reasons)
    }
}
