import Foundation
import OMPWeb
import Testing

/// The JSON envelope: structured errors, never a crash.
@Suite struct EnvelopeTests {
    @Test func malformedRequestsGetStructuredErrors() async {
        let c = Client()
        let ctx = "\"ctx\":{\"now\":\"2026-11-02T04:30:00Z\",\"timeZone\":\"Asia/Kolkata\",\"locale\":\"en-IN\"}"
        let cases: [(String, String)] = [
            ("", "bad_request"), ("{", "bad_request"), ("[]", "bad_request"), ("null", "bad_request"),
            ("42", "bad_request"), ("\"op\"", "bad_request"), ("{}", "bad_request"),
            ("{\"op\":5,\(ctx)}", "bad_request"), ("{\"op\":\"\",\(ctx)}", "bad_request"),
            ("{\"op\":\"household.get\"}", "missing_context"),
            ("{\"op\":\"household.get\",\"ctx\":null}", "missing_context"),
            ("{\"op\":\"household.get\",\"ctx\":{}}", "missing_context"),
            ("{\"op\":\"household.get\",\"ctx\":{\"now\":\"2026-11-02T04:30:00Z\",\"timeZone\":\"Asia/Kolkata\"}}", "missing_context"),
            ("{\"op\":\"household.get\",\"ctx\":{\"now\":\"yesterday\",\"timeZone\":\"Asia/Kolkata\",\"locale\":\"en-IN\"}}", "bad_context"),
            ("{\"op\":\"household.get\",\"ctx\":{\"now\":\"2026-11-02T04:30:00Z\",\"timeZone\":\"Mars/Base\",\"locale\":\"en-IN\"}}", "bad_context"),
            ("{\"op\":\"household.get\",\"ctx\":{\"now\":\"2026-11-02T04:30:00Z\",\"timeZone\":\"Asia/Kolkata\",\"locale\":\"\"}}", "bad_context"),
            ("{\"op\":\"nope.nothing\",\(ctx)}", "unknown_op"),
            ("{\"op\":\"household.get\",\"args\":[],\(ctx)}", "bad_request"),
            ("{\"op\":\"household.create\",\"args\":{\"adults\":\"two\",\"children\":1},\(ctx)}", "bad_request"),
            ("{\"op\":\"household.create\",\"args\":{},\(ctx)}", "bad_request"),
        ]
        for (request, expected) in cases {
            let reply = await c.raw(request)
            #expect(!reply.ok, "\(request) unexpectedly succeeded")
            #expect(reply.code == expected, "\(request) -> \(reply.code ?? "none") (expected \(expected))")
            #expect(!reply.raw.isEmpty && reply.json["error"] != nil)
        }
        // The session still works afterwards.
        #expect((await c.call("household.get")).ok)
    }

    @Test func invalidBytesAreRefusedNotFatal() async {
        let session = FacadeSessionProbe()
        let reply = await session.handle(Data([0xFF, 0xFE, 0x00, 0x7B]))
        #expect(!reply.ok)
        #expect(reply.code == "bad_request")
    }

    @Test func outputIsStableSortedJSON() async {
        let c = Client()
        let a = await c.call("meta.version")
        #expect(a.raw.hasPrefix("{\"ok\":true,\"result\":{"))
        let b = await Client().call("meta.version")
        #expect(a.raw == b.raw)
        let error = await c.call("nope")
        #expect(error.raw.hasPrefix("{\"error\":{\"code\":\"unknown_op\",\"message\":"))
        #expect(error.raw.hasSuffix(",\"ok\":false}"))
    }

    @Test func theSynchronousEntryPointRunsToCompletion() {
        let version = Reply(Facade.handleSync(Data(request("meta.version", "{}").utf8)))
        #expect(version.ok)
        #expect(version.value("protocolVersion") as? Int == 1)
        let created = Reply(Facade.handleSync(Data(request("household.create", "{\"adults\":2,\"children\":1}").utf8)))
        #expect(created.ok, "sync create failed: \(created.raw.prefix(300))")
        let fetched = Reply(Facade.handleSync(Data(request("household.get", "{}").utf8)))
        #expect(fetched.array("household.members").count == 3)
        let refused = Reply(Facade.handleSync(Data(request("plan.generate", "{}").utf8)))
        #expect(refused.code == "gate_refused")
    }
}

func request(_ op: String, _ args: String) -> String {
    "{\"op\":\"\(op)\",\"args\":\(args),\"ctx\":{\"now\":\"2026-11-02T04:30:00Z\",\"timeZone\":\"Asia/Kolkata\",\"locale\":\"en-IN\"}}"
}

/// A bare session for raw byte tests.
struct FacadeSessionProbe {
    let session = FacadeSession()
    func handle(_ data: Data) async -> Reply { Reply(await session.handle(data)) }
}
