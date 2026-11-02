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
