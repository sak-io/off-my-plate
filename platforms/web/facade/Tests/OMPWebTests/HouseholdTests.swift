import Foundation
import Testing

@Suite struct HouseholdTests {
    @Test func createGetNameAndRemove() async {
        let c = Client()
        let empty = await c.call("household.get")
        #expect(empty.ok)
        #expect(empty.string("gate.status") == "noHousehold")

        let created = await c.call("household.create", "{\"adults\":2,\"children\":1}")
        #expect(created.ok)
        #expect(created.array("household.members").count == 3)
        #expect((await c.call("household.create", "{\"adults\":1,\"children\":0}")).code == "household_exists")

        let member = ((created.array("household.members").first as? [String: Any])?["id"] as? String) ?? ""
        let named = await c.call("household.setName", "{\"memberId\":\"\(member)\",\"name\":\"  Meera \"}")
        #expect(named.string("household.members.0.name") == "Meera")
        let cleared = await c.call("household.setName", "{\"memberId\":\"\(member)\",\"name\":\"\"}")
        #expect(cleared.value("household.members.0.name") == nil)
        #expect((await c.call("household.setName", "{\"memberId\":\"ghost\",\"name\":\"x\"}")).code == "invalid_input")

        let removed = await c.call("household.removeMember", "{\"memberId\":\"\(member)\"}")
        #expect(removed.ok)
        let remaining = removed.array("household.members").compactMap { $0 as? [String: Any] }
            .filter { $0["deletedAt"] == nil }
        #expect(remaining.count == 2)
    }

    @Test func sizeIsBounded() async {
        let c = Client()
        #expect((await c.call("household.create", "{\"adults\":0,\"children\":0}")).code == "household_size")
        #expect((await c.call("household.create", "{\"adults\":-1,\"children\":2}")).code == "household_size")
        #expect((await c.call("household.create", "{\"adults\":20,\"children\":20}")).code == "household_size")
        #expect((await c.call("household.get")).string("gate.status") == "noHousehold")
    }

    @Test func theContextDecidesTheDayNotTheHost() async {
        // 10:00 UTC is the 3rd in Kiritimati (+14) and the 1st in Pago Pago (-11).
        let early = Client()
        await early.onboard()
        let east = await early.call("plan.generate", now: "2026-11-02T10:00:00Z", zone: "Pacific/Kiritimati")
        let west = Client()
        await west.onboard()
        let farWest = await west.call("plan.generate", now: "2026-11-02T10:00:00Z", zone: "Pacific/Pago_Pago")
        #expect(east.string("plan.weekStart") == "2026-11-03")
        #expect(farWest.string("plan.weekStart") == "2026-11-01")
    }
}

@Suite struct RemoveMemberRulesTests {
    private func rules(_ reply: Reply) -> [[String: Any]] { reply.array("household.rules").compactMap { $0 as? [String: Any] } }

    @Test func onlyThePersonsOwnRulesAreRemoved() async {
        let c = Client()
        await c.call("household.create", "{\"adults\":2,\"children\":1}")
        let ids = await c.restrictionIDs()
        let household = await c.call("household.get")
        let members = household.array("household.members").compactMap { ($0 as? [String: Any])?["id"] as? String }
        let items = "[{\"restriction\":\"\(ids[0])\",\"scope\":{\"kind\":\"member\",\"memberId\":\"\(members[2])\"}},"
            + "{\"restriction\":\"\(ids[1])\",\"scope\":{\"kind\":\"member\",\"memberId\":\"\(members[1])\"}},"
            + "{\"restriction\":\"\(ids[2])\",\"scope\":{\"kind\":\"household\"}}]"
        #expect((await c.call("safety.confirm", "{\"items\":\(items)}")).ok)
        let removed = await c.call("household.removeMember", "{\"memberId\":\"\(members[2])\",\"removeOwnRules\":true}")
        #expect(removed.ok, "\(removed.raw.prefix(300))")
        let left = rules(removed).compactMap { $0["restriction"] as? String }
        #expect(Set(left) == Set([ids[1], ids[2]]))
        #expect(removed.string("gate.status") == "open")
        // Without the flag the core keeps the rule of a removed person.
        let c2 = Client()
        await c2.call("household.create", "{\"adults\":2,\"children\":0}")
        let m2 = (await c2.call("household.get")).array("household.members").compactMap { ($0 as? [String: Any])?["id"] as? String }
        _ = await c2.call("safety.confirm", "{\"items\":[{\"restriction\":\"\(ids[0])\",\"scope\":{\"kind\":\"member\",\"memberId\":\"\(m2[1])\"}}]}")
        let kept = await c2.call("household.removeMember", "{\"memberId\":\"\(m2[1])\"}")
        #expect(rules(kept).count == 1)
    }

    @Test func aRefusedRemovalLeavesEverythingIntact() async {
        let c = Client()
        await c.call("household.create", "{\"adults\":1,\"children\":0}")
        let ids = await c.restrictionIDs()
        let member = (await c.call("household.get")).string("household.members.0.id") ?? ""
        let saved = await c.call("safety.confirm", "{\"items\":[{\"restriction\":\"\(ids[0])\",\"scope\":{\"kind\":\"member\",\"memberId\":\"\(member)\"}}]}")
        #expect(saved.ok)
        let before = (await c.call("state.export")).raw
        let sole = await c.call("household.removeMember", "{\"memberId\":\"\(member)\",\"removeOwnRules\":true}")
        #expect(sole.code == "safety_transition")
        let unknown = await c.call("household.removeMember", "{\"memberId\":\"ghost\",\"removeOwnRules\":true}")
        #expect(!unknown.ok)
        #expect((await c.call("state.export")).raw == before, "a refused removal must change nothing")
        let after = await c.call("household.get")
        #expect(after.array("household.rules").count == 1)
    }
}
