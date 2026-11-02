import Foundation
import Testing

@Suite struct TimeTests {
    @Test func nowMustBeInAPlausibleRange() async {
        let c = Client()
        for now in ["1999-12-31T23:59:59Z", "2100-01-01T00:00:00Z", "0001-01-01T00:00:00Z", "9999-12-31T23:59:59Z"] {
            #expect((await c.call("meta.version", now: now)).code == "bad_context", "\(now)")
        }
        for now in ["2000-01-01T00:00:00Z", "2099-12-31T23:59:59Z", "2026-11-02T04:30:00.750Z"] {
            #expect((await c.call("meta.version", now: now)).ok, "\(now)")
        }
    }

    /// America/Los_Angeles leaves daylight time at 2026-11-01 09:00 UTC (02:00 PDT -> 01:00 PST).
    @Test func dayBoundariesAcrossADaylightSavingChange() async {
        let zone = "America/Los_Angeles"
        // 00:30 PDT on Nov 1 and 23:30 PST on Nov 1 are the same local day; 00:00 PST on Nov 2 is the next.
        let cases = [
            ("2026-11-01T07:30:00Z", "2026-11-01"), ("2026-11-02T07:30:00Z", "2026-11-01"),
            ("2026-11-02T08:00:00Z", "2026-11-02"), ("2026-11-01T06:59:59Z", "2026-10-31"),
        ]
        for (now, expectedStart) in cases {
            let c = Client()
            // Answer one minute earlier than "now" would be impossible at the lower bound, so onboard at the same instant.
            await c.onboard(adults: 1, children: 0, now: now, zone: zone)
            let reply = await c.call("plan.generate", now: now, zone: zone)
            #expect(reply.ok, "\(now): \(reply.raw.prefix(200))")
            #expect(reply.string("plan.weekStart") == expectedStart, "\(now) in \(zone)")
        }
        // Spring forward: 2026-03-08 10:00 UTC (02:00 PST -> 03:00 PDT).
        for (now, expectedStart) in [("2026-03-08T09:59:00Z", "2026-03-08"), ("2026-03-09T06:59:00Z", "2026-03-08"), ("2026-03-09T07:00:00Z", "2026-03-09")] {
            let c = Client()
            await c.onboard(adults: 1, children: 0, now: now, zone: zone)
            #expect((await c.call("plan.generate", now: now, zone: zone)).string("plan.weekStart") == expectedStart, "\(now)")
        }
    }
}
