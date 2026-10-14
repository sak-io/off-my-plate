import OMPDomain
import OMPServices

/// Everything the onboarding and safety screens call (tasks T22, T18, T16). Built once by the
/// composition root. Screens go through these services only; they never write the household
/// or build a rule themselves, so `SafetyGate` and the validator cannot be bypassed.
public struct SafetyServices: Sendable {
    public let household: HouseholdService
    public let safety: SafetyService
    public let plans: PlanService
    /// Turns typed or spoken text into candidate restrictions (T16). Built from the seed
    /// catalog's keyword table.
    public let parser: SafetyTextParser
    /// The restriction chips in display order (AC-2.5), from the planning library's catalog.
    public let restrictions: [Restriction]

    public init(context: ServiceContext, parser: SafetyTextParser) {
        self.household = HouseholdService(context: context)
        self.safety = SafetyService(context: context)
        self.plans = PlanService(context: context)
        self.parser = parser
        self.restrictions = context.library.restrictions
    }
}
