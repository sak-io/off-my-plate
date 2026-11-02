import Foundation
import OMPWeb
import Testing

/// The committed transcript (Fixtures/transcript.jsonl) replayed through the facade must produce exactly the
/// committed golden responses (Fixtures/transcript.golden.jsonl). CI replays the same transcript with
/// `omp-web-cli` under wasmtime and compares the bytes with the same golden file.
@Suite struct TranscriptTests {
    static let fixtures = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures")

    static let names = ["transcript", "transcript-tz"]

    @Test(arguments: TranscriptTests.names)
    func nativeReplayMatchesTheGolden(name: String) async throws {
        let transcript = try String(contentsOf: Self.fixtures.appendingPathComponent("\(name).jsonl"), encoding: .utf8)
        let output = await TranscriptRunner.run(lines: TranscriptRunner.lines(of: transcript), session: FacadeSession())
        #expect(output.failures.isEmpty, "transcript expectations failed: \(output.failures)")
        let actual = output.responses.joined(separator: "\n") + "\n"
        if let directory = ProcessInfo.processInfo.environment["OMP_GOLDEN_OUT"] {
            try actual.write(toFile: directory + "/\(name).actual.jsonl", atomically: true, encoding: .utf8)
        }
        let golden = (try? String(contentsOf: Self.fixtures.appendingPathComponent("\(name).golden.jsonl"), encoding: .utf8)) ?? ""
        #expect(!golden.isEmpty, "the golden file is missing or empty")
        let expectedLines = golden.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let actualLines = actual.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        #expect(expectedLines.count == actualLines.count, "golden has \(expectedLines.count) lines, replay \(actualLines.count)")
        for (index, pair) in zip(expectedLines, actualLines).enumerated() where pair.0 != pair.1 {
            Issue.record("response \(index + 1) differs from the golden: expected \(pair.0.prefix(200)) got \(pair.1.prefix(200))")
            break
        }
        #expect(actual == golden)
    }

    @Test func theTranscriptCoversTheWholeJourney() async throws {
        let transcript = try String(contentsOf: Self.fixtures.appendingPathComponent("transcript.jsonl"), encoding: .utf8)
        for op in [
            "household.create", "safety.parse", "safety.confirm", "plan.generate", "plan.alternatives", "plan.swap",
            "plan.lock", "plan.approvalPreview", "plan.approve", "state.export", "state.import", "plan.pendingDiff",
        ] {
            #expect(transcript.contains("\"op\":\"\(op)\""), "transcript does not use \(op)")
        }
    }
}
