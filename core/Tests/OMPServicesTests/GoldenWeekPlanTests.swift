import Foundation
import OMPDomain
import OMPRecipes
import OMPServices
import Testing

/// W02: the same seeded household, the same "now" and the same explicit time zone produce the same
/// week plan, byte for byte, on every platform. This test runs in core-linux (native) and in
/// core-wasm (wasm32-wasi under wasmtime) against one committed expected JSON, so the web app's
/// plan equals the native plan. The JSON uses sorted keys and ISO 8601 dates, so only the planner,
/// the seed and the number formatting can make it differ.
@Suite("Golden week plan (native == Wasm)")
struct GoldenWeekPlanTests {
    /// 2026-10-12T00:00:00Z; 05:30 on that Monday in Asia/Kolkata. Time zone and "now" are explicit inputs.
    static let now = Date(timeIntervalSince1970: 1_791_763_200)
    static let zone = TimeZone(identifier: "Asia/Kolkata")!

    static func weekPlanJSON() async throws -> String {
        let seed = try SeedLoader.load(SeedLoader.embeddedFiles())
        let env = ServicesEnv(
            library: PlanningLibrary(seed: seed), clock: TestClock(now: now, timeZone: zone), idPrefix: "golden")
        let created = try await env.households.createHousehold(adults: 2, children: 1)
        let child = created.members[2].id
        _ = try await env.safety.confirmSafetyAnswers([
            RuleRequest(restriction: "peanuts", scope: .member(child))
        ])
        _ = try await env.households.recordCuisines(["southIndian"])
        let draft = try await env.plans.generateWeek()
        #expect(draft.report.passedForEveryone)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return String(decoding: try encoder.encode(draft.plan), as: UTF8.self)
    }

    @Test("the seeded household's week plan equals the committed golden JSON")
    func weekPlanMatchesGolden() async throws {
        let actual = try await Self.weekPlanJSON()
        if let path = ProcessInfo.processInfo.environment["OMP_GOLDEN_OUT"] {
            try actual.write(toFile: path, atomically: true, encoding: .utf8)
            return
        }
        let expected = GoldenWeekPlanFixture.json.trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(!expected.isEmpty, "golden fixture is empty")
        // Compare as a Bool first and describe only the first difference, so a failure stays readable.
        let same = actual == expected
        if same { print("GOLDEN-OK bytes=\(actual.utf8.count)") }
        #expect(same, Comment(rawValue: Self.firstDifference(actual, expected)))
    }

    /// Where two strings first differ, with a little context from each.
    static func firstDifference(_ actual: String, _ expected: String) -> String {
        let a = Array(actual.utf8), e = Array(expected.utf8)
        var index = 0
        while index < a.count, index < e.count, a[index] == e[index] { index += 1 }
        func around(_ bytes: [UInt8]) -> String {
            let from = max(0, index - 60), to = min(bytes.count, index + 60)
            return String(decoding: bytes[from..<to], as: UTF8.self)
        }
        return "first difference at byte \(index) (lengths \(a.count) vs \(e.count)); actual ...\(around(a))... expected ...\(around(e))..."
    }

    @Test("the plan is the same when generated twice (no hidden host input)")
    func repeatable() async throws {
        let first = try await Self.weekPlanJSON()
        let second = try await Self.weekPlanJSON()
        #expect(first == second)
    }
}
