import OMPDomain
import OMPRecipes
import OMPSafetyCheck

/// Module marker for the use cases (`HouseholdService`, `SafetyService`, `PlanService`,
/// `LunchboxService`; T18), repository protocols and in-memory repositories (T03); ADR 0004.
public enum OMPServicesModule {
    /// The core version each linked module was built with, in dependency order.
    public static let linkedVersions: [String] = [
        OMPVersion.current,
        OMPSafetyCheckModule.coreVersion,
        OMPRecipesModule.coreVersion,
    ]
}
