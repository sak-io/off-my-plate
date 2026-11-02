import Foundation
import OMPDomain
import OMPServices

/// A refusal the facade reports as `{"ok":false,"error":{"code","message"[,"details"]}}`.
///
/// The `code` is a stable, documented identifier (docs/windows/w03-report.md); the `message` is for
/// developers and tests, not for display (the web UI maps codes to the copy catalogue).
struct FacadeError: Error, Sendable, Equatable {
    var code: String
    var message: String
    var details: JSONValue?

    init(_ code: String, _ message: String, details: JSONValue? = nil) {
        self.code = code
        self.message = message
        self.details = details
    }

    static func badRequest(_ message: String) -> FacadeError { FacadeError("bad_request", message) }
    static func badContext(_ message: String) -> FacadeError { FacadeError("bad_context", message) }
    static func invalid(_ message: String) -> FacadeError { FacadeError("invalid_input", message) }

    /// Maps anything thrown by the services or the facade to a structured error. Never includes
    /// internals beyond the code and a short generic message.
    static func from(_ error: any Error) -> FacadeError {
        if let facade = error as? FacadeError { return facade }
        if let refusal = error as? GateRefusal { return gate(refusal) }
        if let service = error as? ServiceError { return from(service) }
        if error is InboxImportError { return .invalid("The import is not valid.") }
        if error is DecodingError { return .badRequest("The request arguments are malformed.") }
        return FacadeError("internal_error", "The request could not be completed.")
    }

    static func gate(_ refusal: GateRefusal) -> FacadeError {
        FacadeError("gate_refused", "Safety questions are not answered for everyone.", details: gateDetails(refusal))
    }

    static func gateDetails(_ refusal: GateRefusal) -> JSONValue {
        let reason: String
        switch refusal {
        case .safetyUnanswered: reason = "safetyUnanswered"
        case .reconfirmationDue: reason = "reconfirmationDue"
        }
        return .object([
            "reason": .string(reason),
            "memberIds": .array(refusal.memberIDs.map { .string($0.rawValue) }),
        ])
    }

    private static func from(_ error: ServiceError) -> FacadeError {
        switch error {
        case .noHousehold: return FacadeError("no_household", "Set up the household first.")
        case .householdAlreadyExists: return FacadeError("household_exists", "A household already exists.")
        case .gateRefused(let refusal): return gate(refusal)
        case .clearanceNotValid: return FacadeError("clearance_not_valid", "The safety clearance is no longer valid.")
        case .planNotFound: return FacadeError("plan_not_found", "No such plan.")
        case .notWorkingPlan: return FacadeError("not_working_plan", "That is not the plan being worked on.")
        case .mealNotFound: return FacadeError("meal_not_found", "No such meal.")
        case .mealLocked: return FacadeError("meal_locked", "The meal is locked.")
        case .recipeNotOffered: return FacadeError("recipe_not_offered", "That recipe is not a safe alternative.")
        case .noOtherSafeRecipe: return FacadeError("no_other_safe_recipe", "No other safe recipe exists for that meal.")
        case .validationFailed(let meals):
            return FacadeError(
                "validation_failed", "The independent safety check found a problem; the plan cannot be approved.",
                details: .object(["mealIds": .array(meals.map { .string($0.rawValue) })]))
        case .openDraftExists: return FacadeError("open_draft_exists", "A first plan is still waiting for approval.")
        case .unknownRestriction: return FacadeError("unknown_restriction", "That restriction is not in the catalog.")
        case .lifecycle(let lifecycle):
            switch lifecycle {
            case .wrongStatus: return FacadeError("plan_not_draft", "The plan is not a draft.")
            case .closedPlan: return FacadeError("plan_closed", "The plan is superseded or discarded.")
            case .validationFailed(let meals):
                return FacadeError(
                    "validation_failed", "The independent safety check found a problem; the plan cannot be approved.",
                    details: .object(["mealIds": .array(meals.map { .string($0.rawValue) })]))
            default: return FacadeError("lifecycle_error", "The plan cannot make that transition.")
            }
        case .safetyTransition: return FacadeError("safety_transition", "That safety change is not allowed now.")
        case .householdSize: return FacadeError("household_size", "The household size is out of range.")
        case .markCooked(let refusal):
            let reason: String
            switch refusal {
            case .planNotApproved: reason = "planNotApproved"
            case .blockedBySafety: reason = "blockedBySafety"
            case .alreadyCooked: reason = "alreadyCooked"
            case .mealNotFound: reason = "mealNotFound"
            default: reason = "unavailable"
            }
            return FacadeError(
                "mark_cooked", "Mark cooked is not available for that meal.", details: .object(["reason": .string(reason)]))
        case .pantryItemNotFound: return FacadeError("pantry_item_not_found", "No such pantry item.")
        case .shoppingItemNotFound: return FacadeError("shopping_item_not_found", "No such shopping item.")
        case .factNotFound: return FacadeError("fact_not_found", "No such fact.")
        case .unknownIngredient: return FacadeError("unknown_ingredient", "That ingredient is not in the taxonomy.")
        case .invalidInput(let text): return FacadeError("invalid_input", text)
        default: return FacadeError("service_error", "The request was refused.")
        }
    }
}
