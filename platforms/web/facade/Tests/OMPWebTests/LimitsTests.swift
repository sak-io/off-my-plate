import Foundation
import Testing
@testable import OMPWeb

/// Everything a client sends is bounded at the facade; nothing may trap (a trap kills the Wasm instance).
@Suite struct LimitsTests {
    @Test func householdCountsAreBoundedBeforeAnyArithmetic() async {
        let c = Client()
        let hostile = ["9223372036854775807", "2147483647", "2147483648", "-9223372036854775808", "-1", "-2147483648", "21", "1000000"]
        for value in hostile {
            for (adults, children) in [(value, "1"), ("1", value), (value, value), (value, "0")] {
                let reply = await c.call("household.create", "{\"adults\":\(adults),\"children\":\(children)}")
                #expect(!reply.ok)
                #expect(["household_size", "bad_request"].contains(reply.code ?? ""), "\(adults)/\(children) -> \(reply.code ?? "ok")")
            }
        }
        for tooMany in ["1e30", "0.5", "\"2\"", "null", "[]"] {
            let reply = await c.call("household.create", "{\"adults\":\(tooMany),\"children\":1}")
            #expect(reply.code == "bad_request")
        }
        #expect((await c.call("household.get")).string("gate.status") == "noHousehold")
    }

    @Test func householdBoundaryValues() async {
        for (adults, children, expected) in [(0, 0, "household_size"), (0, 1, ""), (1, 0, ""), (12, 0, ""), (6, 6, ""), (13, 0, "household_size"),
            (20, 0, "household_size"), (0, 20, "household_size"), (20, 20, "household_size"), (21, 0, "household_size"), (0, 21, "household_size")] {
            let reply = await Client().call("household.create", "{\"adults\":\(adults),\"children\":\(children)}")
            if expected.isEmpty {
                #expect(reply.ok, "\(adults)+\(children) should be accepted")
                #expect(reply.array("household.members").count == adults + children)
            } else {
                #expect(reply.code == expected, "\(adults)+\(children) -> \(reply.code ?? "ok")")
            }
        }
    }

    @Test func otherNumbersAndSizesAreBounded() async {
        let c = Client()
        await c.onboard()
        let (id, generated) = await c.generate()
        let meal = generated.string("plan.meals.0.id") ?? ""
        for limit in ["9223372036854775807", "-9223372036854775808", "0", "-1", "2147483647", "100000"] {
            let reply = await c.call("plan.alternatives", "{\"planId\":\"\(id)\",\"mealId\":\"\(meal)\",\"limit\":\(limit)}")
            #expect(reply.ok || reply.code == "bad_request", "limit \(limit) -> \(reply.code ?? "ok")")
            if reply.ok { #expect(reply.array("alternatives").count <= 12) }
        }
        #expect((await c.call("safety.confirmNobody", "{\"pendingItemCount\":9223372036854775807}")).code == "nobody_not_allowed")
        #expect((await c.call("safety.confirmNobody", "{\"pendingItemCount\":-1}")).code == "nobody_not_allowed")
        let manyAbsences = "[" + String(repeating: "{\"memberId\":\"w2\",\"date\":\"2026-11-02\",\"slot\":\"dinner\"},", count: 600) + "{\"memberId\":\"w2\",\"date\":\"2026-11-02\",\"slot\":\"dinner\"}]"
        #expect((await c.call("plan.generate", "{\"absences\":\(manyAbsences)}")).code == "invalid_input")
        let longText = String(repeating: "a", count: 20_001)
        #expect((await c.call("safety.parse", "{\"text\":\"\(longText)\"}")).code == "invalid_input")
        let items = "[" + String(repeating: "{\"unresolvedText\":\"x\"},", count: 300) + "{\"unresolvedText\":\"x\"}]"
        #expect((await c.call("safety.confirm", "{\"items\":\(items)}")).code == "invalid_input")
        let member = (await c.call("household.get")).string("household.members.0.id") ?? ""
        let longName = String(repeating: "n", count: 201)
        #expect((await c.call("household.setName", "{\"memberId\":\"\(member)\",\"name\":\"\(longName)\"}")).code == "invalid_input")
        let deep = String(repeating: "[", count: 3000) + String(repeating: "]", count: 3000)
        let reply = await c.raw(request("household.get", "{\"x\":\(deep)}"))
        #expect(!reply.ok && reply.code != nil)
    }

    @Test func oversizedRequestsAreRefused() async {
        let big = Data(repeating: 0x20, count: 8 * 1024 * 1024 + 1)
        let reply = Reply(await FacadeSession().handle(big))
        #expect(reply.code == "request_too_large")
        let ok = Reply(await FacadeSession().handle(Data(request("meta.version", "{}").utf8)))
        #expect(ok.ok)
    }

    @Test func duplicateKeysAreRejected() async {
        let c = Client()
        let ctx = "\"ctx\":{\"now\":\"2026-11-02T04:30:00Z\",\"timeZone\":\"Asia/Kolkata\",\"locale\":\"en-IN\"}"
        let cases = [
            "{\"op\":\"meta.version\",\"op\":\"nope\",\(ctx)}",
            "{\"op\":\"gate.status\",\"args\":{\"a\":1,\"a\":2},\(ctx)}",
            "{\"op\":\"gate.status\",\"args\":{\"a\":1,\"\\u0061\":2},\(ctx)}",
            "{\"op\":\"gate.status\",\"args\":{\"x\":[{\"k\":1,\"k\":2}]},\(ctx)}",
        ]
        for text in cases {
            #expect((await c.raw(text)).code == "duplicate_key", "\(text.prefix(80))")
        }
        // The same key in different objects, and a key text inside a value, are fine.
        let fine = "{\"op\":\"gate.status\",\"args\":{\"a\":{\"a\":1},\"b\":[{\"a\":1},{\"a\":2}],\"c\":\"a\"},\(ctx)}"
        #expect((await c.raw(fine)).ok)
    }

    @Test func aStuckCallIsAbandonedNotHung() {
        let outcome = SyncRunner.run(maxIdleRounds: 3) {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in _ = continuation }
            return Data("never".utf8)
        }
        #expect(outcome.stalled)
        #expect(Reply(outcome.data).code == "executor_stalled")
        let fine = SyncRunner.run { Data("done".utf8) }
        #expect(!fine.stalled && String(decoding: fine.data, as: UTF8.self) == "done")
    }
}
