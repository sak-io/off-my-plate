import Foundation
import OMPDomain
import OMPServices

/// Everything the browser can ask of the Swift core, behind one JSON entry point (ADR 0016).
///
/// ```
/// request : {"op":"household.get","args":{...},"ctx":{"now":"2026-11-02T04:30:00Z","timeZone":"Asia/Kolkata","locale":"en-IN"}}
/// success : {"ok":true,"result":{...}}
/// failure : {"error":{"code":"...","message":"..."[,"details":{...}]},"ok":false}
/// ```
///
/// `ctx` is required on every call. State lives in in-memory repositories owned by the session and is
/// saved/restored by the browser through `state.export` / `state.import`. Calls are serialised by the
/// actor; the host must not interleave them (the Wasm entry is synchronous, so it cannot).
public actor FacadeSession {
    let clock: FacadeClock
    var engine: Engine
    let contentResult: Result<SeedContent, FacadeError>

    /// A fresh, empty session.
    public init() {
        let clock = FacadeClock()
        self.clock = clock
        let result = SeedContent.shared
        contentResult = result
        switch result {
        case .success(let content):
            engine = Engine(repositories: .inMemory(), clock: clock, ids: IDSource(), content: content)
        case .failure:
            // Placeholder never used: `handle` answers `seed_unavailable` before touching it.
            engine = Engine(
                repositories: .inMemory(), clock: clock, ids: IDSource(),
                content: SeedContent(
                    library: PlanningLibrary(recipes: [], ingredients: [], restrictions: [], contentVersion: "none"),
                    parser: SafetyTextParser(keywords: [:])))
        }
    }

    /// Handles one request document and returns one response document. Never throws; never crashes on
    /// malformed input.
    public func handle(_ requestJSON: Data) async -> Data {
        do {
            let content = try contentResult.get()
            let request = try Request.parse(requestJSON)
            clock.set(request.context)
            let result = try await dispatch(request, content: content)
            return Response.success(result)
        } catch {
            return Response.failure(FacadeError.from(error))
        }
    }

    func replaceEngine(_ new: Engine) {
        engine = new
    }
}

/// A parsed request envelope.
struct Request: Sendable {
    let op: String
    let args: JSONValue
    let context: CallContext

    static func parse(_ data: Data) throws -> Request {
        let value: JSONValue
        do {
            value = try JSONDecoder().decode(JSONValue.self, from: data)
        } catch {
            throw FacadeError.badRequest("The request is not valid JSON.")
        }
        guard case .object = value, let op = value["op"]?.stringValue, !op.isEmpty else {
            throw FacadeError.badRequest("The request needs an \"op\" string.")
        }
        // ctx is checked before the op is looked up, so a missing context is always reported as such.
        let context = try CallContext.parse(value["ctx"])
        var args = value["args"] ?? .object([:])
        if case .null = args { args = .object([:]) }
        guard case .object = args else { throw FacadeError.badRequest("\"args\" must be an object.") }
        return Request(op: op, args: args, context: context)
    }

    func decode<T: Decodable>(_ type: T.Type) throws -> T {
        do {
            let data = try JSONEncoder().encode(args)
            return try CanonicalJSON.decoder().decode(T.self, from: data)
        } catch let error as DecodingError {
            switch error {
            case .keyNotFound(let key, _):
                throw FacadeError.badRequest("Missing argument \"\(key.stringValue)\".")
            case .typeMismatch(_, let context), .valueNotFound(_, let context), .dataCorrupted(let context):
                let path = context.codingPath.map(\.stringValue).joined(separator: ".")
                throw FacadeError.badRequest("Invalid argument \"\(path)\".")
            @unknown default:
                throw FacadeError.badRequest("The request arguments are malformed.")
            }
        }
    }
}

enum Response {
    static func success(_ result: Data) -> Data {
        var out = Data("{\"ok\":true,\"result\":".utf8)
        out.append(result)
        out.append(Data("}".utf8))
        return out
    }

    static func failure(_ error: FacadeError) -> Data {
        var fields: [String: JSONValue] = [
            "code": .string(error.code), "message": .string(error.message),
        ]
        if let details = error.details { fields["details"] = details }
        let tree = JSONValue.object(["ok": .bool(false), "error": .object(fields)])
        // Encoding a tree of strings cannot fail; fall back to a fixed document anyway.
        return (try? CanonicalJSON.encode(tree: tree))
            ?? Data("{\"error\":{\"code\":\"internal_error\",\"message\":\"\"},\"ok\":false}".utf8)
    }
}

/// The default process-wide session used by the Wasm entry points.
public enum Facade {
    public static let shared = FacadeSession()

    /// Handles one request document on the shared session.
    public static func handle(_ requestJSON: Data) async -> Data {
        await shared.handle(requestJSON)
    }

    /// Synchronous variant for hosts without threads (the Wasm exports). Drives the async services to
    /// completion on the calling thread; see `SyncRunner`.
    public static func handleSync(_ requestJSON: Data) -> Data {
        SyncRunner.run { await shared.handle(requestJSON) }
    }
}
