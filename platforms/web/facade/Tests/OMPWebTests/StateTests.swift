import Foundation
import OMPWeb
import Testing

/// state.export / state.import: the browser persists the snapshot; import must not be a side door.
@Suite struct StateTests {
    private func mutated(_ snapshot: Any, _ change: (inout [String: Any]) -> Void) -> String {
        var object = (snapshot as? [String: Any]) ?? [:]
        change(&object)
        let data = (try? JSONSerialization.data(withJSONObject: ["snapshot": object])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    private func importRequest(_ snapshotJSON: String) -> String {
        request("state.import", snapshotJSON.hasPrefix("{\"snapshot\"") ? snapshotJSON : "{\"snapshot\":\(snapshotJSON)}")
    }

    @Test func exportImportRoundTripIsLossless() async {
        let a = Client()
        await a.onboard()
        let (id, _) = await a.generate()
        #expect((await a.approve(id)).ok)
        let export = await a.call("state.export")
        #expect(export.ok)
        #expect(export.value("snapshot.version") as? Int == 1)
        #expect(export.string("snapshot.format") == "omp-web-state")

        let b = Client()
        let body = String(export.raw.dropFirst("{\"ok\":true,\"result\":".count).dropLast())
        let imported = await b.raw(request("state.import", body))
        #expect(imported.ok, "import failed: \(imported.raw.prefix(300))")
        #expect(imported.bool("imported") == true)
        let again = await b.call("state.export")
        #expect(again.raw == export.raw)
        // The approval survived and is still effective; the gate is still open.
        let current = await b.call("plan.current")
        #expect(current.bool("approved.effectivelyApproved") == true)
        #expect(current.string("gate.status") == "open")
        // New ids do not collide with the imported ones: editing the approved plan makes a draft revision.
        let mealID = current.string("approved.plan.meals.0.id") ?? ""
        let revised = await b.call("plan.lock", "{\"planId\":\"\(id)\",\"mealId\":\"\(mealID)\"}")
        #expect(revised.ok, "edit after import failed: \(revised.raw.prefix(300))")
        #expect(revised.string("plan.status") == "draft")
        #expect(revised.string("plan.id") != id)
    }

    @Test func importRejectsGarbageWithoutTouchingTheCurrentState() async {
        let a = Client()
        await a.onboard()
        let (id, _) = await a.generate()
        #expect((await a.approve(id)).ok)
        let export = await a.call("state.export")
        let snapshot: Any = export.value("snapshot") ?? [String: Any]()
        let before = (await a.call("state.export")).raw

        let tampered = mutated(snapshot) { object in
            var plans = (object["mealPlans"] as? [[String: Any]]) ?? []
            if !plans.isEmpty {
                var approval = (plans[0]["approval"] as? [String: Any]) ?? [:]
                approval["contentHash"] = String(repeating: "0", count: 64)
                plans[0]["approval"] = approval
            }
            object["mealPlans"] = plans
        }
        let forgedApproval = mutated(snapshot) { object in
            var plans = (object["mealPlans"] as? [[String: Any]]) ?? []
            if !plans.isEmpty {
                plans[0]["status"] = "approved"
                plans[0].removeValue(forKey: "approval")
            }
            object["mealPlans"] = plans
        }
        let draftWithApproval = mutated(snapshot) { object in
            var plans = (object["mealPlans"] as? [[String: Any]]) ?? []
            if !plans.isEmpty { plans[0]["status"] = "draft" }
            object["mealPlans"] = plans
        }
        let newer = mutated(snapshot) { $0["version"] = 99 }
        let wrongFormat = mutated(snapshot) { $0["format"] = "something-else" }
        let noMembers = mutated(snapshot) { object in
            var household = (object["household"] as? [String: Any]) ?? [:]
            household["members"] = [Any]()
            object["household"] = household
        }
        let duplicatePlans = mutated(snapshot) { object in
            let plans = (object["mealPlans"] as? [Any]) ?? []
            object["mealPlans"] = plans + plans
        }
        let negativeCounter = mutated(snapshot) { $0["idCounter"] = -5 }
        let missingField = mutated(snapshot) { $0.removeValue(forKey: "mealPlans") }
        let badDate = mutated(snapshot) { object in
            var household = (object["household"] as? [String: Any]) ?? [:]
            household["createdAt"] = "last tuesday"
            object["household"] = household
        }

        let cases: [(String, String)] = [
            (tampered, "invalid_state"), (forgedApproval, "invalid_state"), (draftWithApproval, "invalid_state"),
            (newer, "unsupported_state_version"), (wrongFormat, "invalid_state"), (noMembers, "invalid_state"),
            (duplicatePlans, "invalid_state"), (negativeCounter, "invalid_state"), (missingField, "invalid_state"),
            (badDate, "invalid_state"),
            ("{\"snapshot\":42}", "invalid_state"), ("{\"snapshot\":[]}", "invalid_state"),
            ("{\"snapshot\":null}", "invalid_state"), ("{\"snapshot\":\"text\"}", "invalid_state"),
        ]
        for (body, expected) in cases {
            let reply = await a.raw(importRequest(body))
            #expect(!reply.ok)
            #expect(reply.code == expected, "\(body.prefix(120)) -> \(reply.code ?? "ok") (expected \(expected))")
        }
        let noSnapshot = await a.call("state.import", "{}")
        #expect(noSnapshot.code == "bad_request")
        // No partial application: the state is byte-for-byte what it was.
        let after = (await a.call("state.export")).raw
        #expect(after == before)
    }

    @Test func importOfAnEmptySessionClearsNothingBeforeItSucceeds() async {
        let empty = await Client().call("state.export")
        #expect(empty.ok)
        #expect(empty.value("snapshot.household") == nil)
        #expect(empty.array("snapshot.mealPlans").isEmpty)
    }
}
