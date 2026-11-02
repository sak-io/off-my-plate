import Foundation

/// Replays a transcript: lines of JSON requests, one response line each. Used by the native tests, by
/// `omp-web-cli` natively and under wasmtime, so one fixture proves the same bytes everywhere.
///
/// Besides request lines, a transcript may contain directives (they produce no output line):
/// - `# text`                          a comment
/// - `@capture NAME PATH`              store the value at PATH (dotted, "result.plan.id") of the previous
///                                     response; later request lines may contain `{{NAME}}`
/// - `@expect ok` / `@expect error CODE`   check the previous response; mismatches are reported in
///                                     `failures` (not in the golden output)
public enum TranscriptRunner {
    public struct Output: Sendable {
        /// One response document per request line.
        public var responses: [String]
        /// Failed `@expect` checks and unresolvable captures.
        public var failures: [String]
    }

    public static func run(lines: [String], session: FacadeSession) async -> Output {
        var responses: [String] = []
        var failures: [String] = []
        var variables: [String: String] = [:]
        var last: JSONValue?

        for (offset, rawLine) in lines.enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            let label = "line \(offset + 1)"
            if line.isEmpty || line.hasPrefix("#") { continue }
            if line.hasPrefix("@capture ") {
                let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
                guard parts.count == 3, let tree = last, let value = tree.value(atPath: parts[2]) else {
                    failures.append("\(label): cannot capture \(line)")
                    continue
                }
                switch value {
                case .string(let text): variables[parts[1]] = text
                case .int(let number): variables[parts[1]] = String(number)
                case .null:
                    failures.append("\(label): captured value is null")
                default:
                    // Objects, arrays and booleans are stored as canonical JSON text (for {"snapshot": {{snap}}}).
                    if let data = try? CanonicalJSON.encode(tree: value) {
                        variables[parts[1]] = String(decoding: data, as: UTF8.self)
                    }
                }
                continue
            }
            if line.hasPrefix("@expect ") {
                let words = line.split(separator: " ").map(String.init)
                let isOK: Bool
                if case .bool(let flag)? = last?["ok"] { isOK = flag } else { isOK = false }
                if words.count == 2, words[1] == "ok" {
                    if !isOK { failures.append("\(label): expected ok but the previous response failed") }
                } else if words.count == 3, words[1] == "error" {
                    let code = last?["error"]?["code"]?.stringValue
                    if isOK || code != words[2] {
                        failures.append("\(label): expected error \(words[2]), got \(code ?? "success")")
                    }
                } else {
                    failures.append("\(label): bad directive \(line)")
                }
                continue
            }
            var request = line
            for (name, value) in variables { request = request.replacingOccurrences(of: "{{\(name)}}", with: value) }
            if request.contains("{{") { failures.append("\(label): unresolved variable in request") }
            let response = await session.handle(Data(request.utf8))
            let text = String(decoding: response, as: UTF8.self)
            responses.append(text)
            last = try? JSONDecoder().decode(JSONValue.self, from: response)
        }
        return Output(responses: responses, failures: failures)
    }

    public static func lines(of text: String) -> [String] {
        text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }
}
