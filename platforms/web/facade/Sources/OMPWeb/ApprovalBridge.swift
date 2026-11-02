import Foundation
import OMPDomain
import OMPServices

// ApprovalBridge.swift: the ONLY file in the web platform that creates a `UserConfirmation`.
//
// What this guarantees, and what it cannot.
//
// A `UserConfirmation` is the core's proof that a person pressed "Approve" (AC-5.2, AC-5.6, ADR 0008).
// On iOS the proof is a SwiftUI button handler. A WebAssembly module cannot see a pointer, a keyboard or
// a click: it only ever receives bytes from JavaScript. So this file does NOT and CANNOT prove a human
// click. What it enforces instead is a narrow, auditable door:
//
//   1. Exactly one place constructs the confirmation: the handler below, for the operation
//      "plan.approve". scripts/lint-safety.sh allows that constructor in this exact file (not a glob)
//      and CODEOWNERS requires the owner's review for any change to it. No other operation, helper,
//      alias or typealias can produce one, and there is no "approve everything" operation.
//   2. The request must name the gesture "confirm-button". Anything else is refused. This is a
//      deliberate-intent check on the message, not a security boundary against hostile JavaScript.
//   3. The request must echo the content hash of the plan the approval sheet showed
//      ("plan.approvalPreview" returns it; the preview records nothing). If the plan changed since
//      (swap, lock, regenerate, an R1 re-check...), the hash differs and the answer is
//      "stale_preview": the person approves exactly what the sheet displayed, never something newer.
//   4. Only then PlanService.approve runs. It still re-reads the household, refuses while anyone is
//      unasked, and re-runs the independent validator against the CURRENT rules before it approves
//      (ADR 0007), so a stale or forged request cannot approve an unsafe plan.
//
// The remaining link, "this message came from a real tap on a visible, unobscured Approve button",
// lives in the web UI (W06): its tests must show that only the approval sheet's button sends
// "plan.approve", that voice/typed text can at most open the sheet, and that the button is disabled
// while the plan is blocked. A compromised page can always send this message; the browser app is the
// user's own code on the user's own device (no accounts, no server), the same trust as the iOS app.

/// What `plan.approve` answers with.
struct ApprovalResult: Encodable {
    var approved: PlanView
    var superseded: PlanView?
}

enum ApprovalBridge {
    /// The only gesture the bridge accepts.
    static let confirmGesture = "confirm-button"

    private struct Args: Decodable {
        var planId: MealPlanID
        var shownContentHash: String
        var gesture: String
    }

    static func approve(_ request: Request, plans: PlanService, repositories: Repositories) async throws
        -> ApprovalResult
    {
        let args = try request.decode(Args.self)
        guard args.gesture == confirmGesture else {
            throw FacadeError(
                "approval_gesture_required", "Approval needs the \"confirm-button\" gesture from the approval sheet.")
        }
        guard let plan = try await repositories.mealPlans.fetch(id: args.planId) else {
            throw FacadeError.from(ServiceError.planNotFound(args.planId))
        }
        guard plan.contentHash == args.shownContentHash else {
            throw FacadeError(
                "stale_preview", "The plan changed after the approval sheet was shown; review it again.")
        }
        let confirmation = UserConfirmation()
        let outcome = try await plans.approve(args.planId, confirmation: confirmation)
        return ApprovalResult(approved: PlanView(outcome.approved), superseded: outcome.superseded.map { PlanView($0) })
    }
}
