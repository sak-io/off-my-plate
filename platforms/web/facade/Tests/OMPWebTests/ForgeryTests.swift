import Foundation
import Testing

/// A snapshot comes from the browser's storage: it must never be a way around the gate, the validator or
/// the approval rules (round-1 review of W03).
@Suite struct ForgeryTests {
    /// A household that was onboarded, with one approved plan, exported as a mutable object.
    private func approvedState() async -> (client: Client, planID: String, snapshot: [String: Any]) {
        let c = Client()
        await c.onboard(adults: 2, children: 0)
        let (id, _) = await c.generate()
        let approved = await c.approve(id)
        #expect(approved.ok)
        let export = await c.call("state.export")
        return (c, id, (export.value("snapshot") as? [String: Any]) ?? [:])
    }

    private func body(_ snapshot: [String: Any]) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: ["snapshot": snapshot])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    private func household(_ snapshot: [String: Any]) -> [String: Any] { (snapshot["household"] as? [String: Any]) ?? [:] }

    @Test func anApprovedPlanThatBreaksTheSnapshotsOwnRulesComesInFlagged() async {
        let (source, planID, snapshot) = await approvedState()
        let catalog = await source.call("safety.catalog")
        var rules: [[String: Any]] = []
        for (index, item) in catalog.array("restrictions").enumerated() {
            guard let restriction = item as? [String: Any] else { continue }
            rules.append([
                "id": "forged\(index)", "kind": "hard", "scope": ["household": [String: Any]()],
                "restriction": restriction["id"] ?? "", "excludedTags": restriction["excludedTags"] ?? [],
                "source": "user", "createdAt": "2026-11-02T04:30:00Z",
            ])
        }
        var forged = snapshot
        var forgedHousehold = household(snapshot)
        forgedHousehold["rules"] = rules
        forged["household"] = forgedHousehold

        let target = Client()
        let imported = await target.call("state.import", body(forged))
        #expect(imported.ok, "import failed: \(imported.raw.prefix(300))")
        // The hash still matches, so the plan is "approved", but the independent validator flagged it.
        #expect(!imported.strings("recheck.blockedMealIds").isEmpty)
        let current = await target.call("plan.current")
        #expect(current.bool("approved.effectivelyApproved") == true)
        #expect(!current.strings("approved.blockedMealIds").isEmpty, "blocked meals must be flagged, not trusted")
        // It cannot be approved again, and nothing else turned into an approval.
        let again = await target.approve(planID)
        #expect(!again.ok)
        for plan in await target.exportedPlans() where plan["status"] as? String == "draft" {
            #expect(plan["approval"] == nil)
        }
        // A proposed revision, if any, still goes through the validator when approved.
        for draft in imported.strings("recheck.proposedDraftIds") {
            let reply = await target.approve(draft)
            if reply.ok { #expect(reply.strings("approved.blockedMealIds").isEmpty) } else { #expect(reply.code != nil) }
        }
    }

    @Test func unansweredAndOverdueMembersStillBlockPlanningAfterImport() async {
        let (_, _, snapshot) = await approvedState()
        // (b1) everyone unasked
        var unasked = snapshot
        var unaskedHousehold = household(snapshot)
        unaskedHousehold["members"] = ((unaskedHousehold["members"] as? [[String: Any]]) ?? []).map { member -> [String: Any] in
            var copy = member
            copy["safetyStatus"] = "unasked"
            copy.removeValue(forKey: "safetyConfirmedAt")
            return copy
        }
        unasked["household"] = unaskedHousehold
        let a = Client()
        #expect((await a.call("state.import", body(unasked))).ok)
        #expect((await a.call("gate.status")).string("status") == "refused")
        #expect((await a.call("plan.generate")).code == "gate_refused")
        // (b2) answered long ago: re-confirmation is due
        var overdue = snapshot
        var overdueHousehold = household(snapshot)
        overdueHousehold["members"] = ((overdueHousehold["members"] as? [[String: Any]]) ?? []).map { member -> [String: Any] in
            var copy = member
            copy["safetyConfirmedAt"] = "2025-01-01T00:00:00Z"
            return copy
        }
        overdue["household"] = overdueHousehold
        let b = Client()
        #expect((await b.call("state.import", body(overdue))).ok)
        let gate = await b.call("gate.status")
        #expect(gate.string("status") == "refused")
        #expect(gate.string("reason") == "reconfirmationDue")
        #expect((await b.call("plan.generate")).code == "gate_refused")
    }

    @Test func twoApprovedPlansInOneSeriesAreRejected() async {
        let (_, _, snapshot) = await approvedState()
        var plans = (snapshot["mealPlans"] as? [[String: Any]]) ?? []
        var copy = plans[0]
        copy["id"] = "dup-1"
        copy["revision"] = 2
        plans.append(copy)
        var forged = snapshot
        forged["mealPlans"] = plans
        let reply = await Client().call("state.import", body(forged))
        #expect(reply.code == "invalid_state")
    }

    @Test func structuralForgeriesAreRejected() async {
        let (_, _, snapshot) = await approvedState()
        // plans without a household
        var noHousehold = snapshot
        noHousehold.removeValue(forKey: "household")
        #expect((await Client().call("state.import", body(noHousehold))).code == "invalid_state")
        // a rule for a member that does not exist
        var ghost = snapshot
        var ghostHousehold = household(snapshot)
        ghostHousehold["rules"] = [[
            "id": "r1", "kind": "hard", "scope": ["member": ["_0": "ghost"]], "restriction": "x", "excludedTags": [String](),
            "source": "user", "createdAt": "2026-11-02T04:30:00Z",
        ]]
        ghost["household"] = ghostHousehold
        #expect((await Client().call("state.import", body(ghost))).code == "invalid_state")
        // dates that would trap calendar maths
        var farFuture = snapshot
        var plans = (snapshot["mealPlans"] as? [[String: Any]]) ?? []
        plans[0]["weekStart"] = "9999-12-30"
        farFuture["mealPlans"] = plans
        #expect((await Client().call("state.import", body(farFuture))).code == "invalid_state")
        var ancient = snapshot
        var ancientHousehold = household(snapshot)
        ancientHousehold["createdAt"] = "1999-12-31T23:59:59Z"
        ancient["household"] = ancientHousehold
        #expect((await Client().call("state.import", body(ancient))).code == "invalid_state")
        // revision at the top of Int: the core adds one when it makes a draft revision
        var huge = snapshot
        var hugePlans = (snapshot["mealPlans"] as? [[String: Any]]) ?? []
        hugePlans[0]["revision"] = Int64.max
        huge["mealPlans"] = hugePlans
        #expect((await Client().call("state.import", body(huge))).code == "invalid_state")
        var counter = snapshot
        counter["idCounter"] = Int64.max
        let reply = await Client().call("state.import", body(counter))
        #expect(reply.code == "invalid_state")
    }

    @Test func theIdCounterIsRaisedAboveEveryIdInTheState() async {
        let (_, planID, snapshot) = await approvedState()
        var lowered = snapshot
        lowered["idCounter"] = 0
        let target = Client()
        #expect((await target.call("state.import", body(lowered))).ok)
        let export = await target.call("state.export")
        let counter = export.value("snapshot.idCounter") as? Int ?? -1
        #expect(counter >= 4, "the counter must be above ids already in use, got \(counter)")
        // New entities get fresh ids: editing the approved plan makes a revision with a new id, and the
        // approved plan is not overwritten.
        let current = await target.call("plan.current")
        let meal = current.string("approved.plan.meals.0.id") ?? ""
        let revised = await target.call("plan.lock", "{\"planId\":\"\(planID)\",\"mealId\":\"\(meal)\"}")
        #expect(revised.ok)
        let plans = await target.exportedPlans()
        let ids = plans.compactMap { $0["id"] as? String }
        #expect(Set(ids).count == ids.count && ids.count == 2)
        #expect(plans.contains { $0["id"] as? String == planID && $0["status"] as? String == "approved" })
        let added = await target.call("household.addMember", "{\"role\":\"adult\"}")
        let memberIDs = added.array("household.members").compactMap { ($0 as? [String: Any])?["id"] as? String }
        #expect(Set(memberIDs).count == memberIDs.count)
    }

    @Test func aClockBehindTheStoredDataIsRefused() async {
        let (source, _, snapshot) = await approvedState()
        let earlier = "2026-11-01T00:00:00Z"
        let into = Client()
        #expect((await into.call("state.import", body(snapshot), now: earlier)).code == "clock_behind_state")
        // ... and nothing was imported
        #expect((await into.call("household.get", now: earlier)).string("gate.status") == "noHousehold")
        // On a live session: every time-dependent op refuses, export and version still work.
        #expect((await source.call("household.get", now: earlier)).code == "clock_behind_state")
        #expect((await source.call("plan.generate", now: earlier)).code == "clock_behind_state")
        #expect((await source.call("state.export", now: earlier)).ok)
        #expect((await source.call("meta.version", now: earlier)).ok)
    }
}
