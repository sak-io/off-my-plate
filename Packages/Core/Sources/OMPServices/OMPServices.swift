import OMPDomain
import OMPRecipes
import OMPSafetyCheck

/// Placeholder for the use cases, repository protocols and in-memory repositories
/// (ADR 0004, tasks T03, T18 and T19).
///
/// Exists so the target builds and links all three Core modules from day one.
public enum OMPServicesModule {
    /// The core version each linked module was built with, in dependency order.
    public static let linkedVersions: [String] = [
        OMPVersion.current,
        OMPSafetyCheckModule.coreVersion,
        OMPRecipesModule.coreVersion,
    ]
}
