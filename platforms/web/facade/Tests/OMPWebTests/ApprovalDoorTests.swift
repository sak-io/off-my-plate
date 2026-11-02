import Foundation
import Testing

/// AC-5.2, AC-5.6, ADR 0008: the only way to approve is `plan.approve` with the confirm gesture and the
/// hash of the content that was shown.
@Suite struct ApprovalDoorTests {
    @Test func approvalNeedsTheConfirmButtonGesture() async {
        let c = Client()
        await c.onboard()
        let (id, _) = await c.generate()
        let preview = await c.call("plan.approvalPreview", "{\"planId\":\"\(id)\"}")
        let hash = preview.string("plan.contentHash") ?? "missing"
        #expect(preview.bool("canApprove") == true)

        for gesture in ["voice", "tap", "", "CONFIRM-BUTTON", "confirm-button "] {
            let reply = await c.call(
                "plan.approve", "{\"planId\":\"\(id)\",\"shownContentHash\":\"\(hash)\",\"gesture\":\"\(gesture)\"}")
            #expect(!reply.ok)
            #expect(reply.code == "approval_gesture_required")
        }
        let noGesture = await c.call("plan.approve", "{\"planId\":\"\(id)\",\"shownContentHash\":\"\(hash)\"}")
        #expect(noGesture.code == "bad_request")
        let noHash = await c.call("plan.approve", "{\"planId\":\"\(id)\",\"gesture\":\"confirm-button\"}")
        #expect(noHash.code == "bad_request")
        let nothing = await c.call("plan.approve")
        #expect(nothing.code == "bad_request")

        let still = await c.call("plan.get", "{\"planId\":\"\(id)\"}")
        #expect(still.string("plan.status") == "draft")
        #expect(still.value("plan.approval") == nil)
    }

    @Test func approvalWithAWrongOrStaleHashIsRefused() async {
        let c = Client()
        await c.onboard()
        let (id, _) = await c.generate()
        let wrong = await c.call(
            "plan.approve",
            "{\"planId\":\"\(id)\",\"shownContentHash\":\"\(String(repeating: "0", count: 64))\",\"gesture\":\"confirm-button\"}")
        #expect(wrong.code == "stale_preview")

        // The person saw hash H; before they tapped, the plan changed (a meal was locked).
        let preview = await c.call("plan.approvalPreview", "{\"planId\":\"\(id)\"}")
        let shown = preview.string("plan.contentHash") ?? "missing"
        let mealID = preview.string("plan.plan.meals.0.id") ?? preview.string("plan.meals.0.id") ?? ""
        let changed = await c.call("plan.lock", "{\"planId\":\"\(id)\",\"mealId\":\"\(mealID)\"}")
        #expect(changed.ok)
        #expect(changed.string("contentHash") != shown)
        let stale = await c.call(
            "plan.approve", "{\"planId\":\"\(id)\",\"shownContentHash\":\"\(shown)\",\"gesture\":\"confirm-button\"}")
        #expect(stale.code == "stale_preview")

        let after = await c.call("plan.get", "{\"planId\":\"\(id)\"}")
        #expect(after.string("plan.status") == "draft")
    }

    @Test func approvingTheShownContentWorks() async {
        let c = Client()
        await c.onboard()
        let (id, generated) = await c.generate()
        #expect(generated.string("plan.status") == "draft")
        let approved = await c.approve(id)
        #expect(approved.ok, "approve failed: \(approved.raw.prefix(300))")
        #expect(approved.string("approved.plan.status") == "approved")
        #expect(approved.bool("approved.effectivelyApproved") == true)
        #expect(approved.string("approved.plan.approval.contentHash") == approved.string("approved.contentHash"))

        // A second approval of the same plan is refused: it is no longer a draft.
        let again = await c.approve(id)
        #expect(!again.ok)
        #expect(again.code == "plan_not_draft")
    }

    @Test func approvingAnUnknownPlanFails() async {
        let c = Client()
        await c.onboard()
        let reply = await c.call(
            "plan.approve",
            "{\"planId\":\"nope\",\"shownContentHash\":\"abc\",\"gesture\":\"confirm-button\"}")
        #expect(reply.code == "plan_not_found")
    }

    @Test func approvalIsRefusedWhileSomeoneIsUnasked() async {
        let c = Client()
        await c.onboard()
        let (id, _) = await c.generate()
        let added = await c.call("household.addMember", "{\"role\":\"adult\"}")
        #expect(added.ok)
        #expect(added.string("gate.status") == "refused")
        let preview = await c.call("plan.approvalPreview", "{\"planId\":\"\(id)\"}")
        #expect(preview.bool("canApprove") == false)
        let reply = await c.approve(id)
        #expect(reply.code == "gate_refused")
        #expect((await c.call("plan.get", "{\"planId\":\"\(id)\"}")).string("plan.status") == "draft")
    }

    @Test func approvalConstructorLivesInOneFileOnly() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources")
        var holders: [String] = []
        var scanned = 0
        let walker = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)
        while let url = walker?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            scanned += 1
            let text = try String(contentsOf: url, encoding: .utf8)
            let code = text.split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            if code.contains(where: { $0.contains("UserConfirmation") }) { holders.append(url.lastPathComponent) }
        }
        #expect(scanned >= 8)
        #expect(holders == ["ApprovalBridge.swift"])
    }
}
