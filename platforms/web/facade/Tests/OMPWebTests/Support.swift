import Foundation
import OMPWeb
import Testing

/// One decoded response document.
struct Reply {
    let raw: String
    let json: [String: Any]

    init(_ data: Data) {
        raw = String(decoding: data, as: UTF8.self)
        json = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any]) ?? [:]
    }

    var ok: Bool { (json["ok"] as? Bool) ?? false }
    var code: String? { ((json["error"] as? [String: Any])?["code"]) as? String }

    /// The value at a dotted path below "result" ("plan.meals.0.id").
    func value(_ path: String) -> Any? {
        var current: Any? = json["result"]
        for segment in path.split(separator: ".").map(String.init) {
            if let dictionary = current as? [String: Any] {
                current = dictionary[segment]
            } else if let array = current as? [Any], let index = Int(segment), array.indices.contains(index) {
                current = array[index]
            } else {
                return nil
            }
        }
        return current
    }

    func string(_ path: String) -> String? { value(path) as? String }
    func bool(_ path: String) -> Bool? { value(path) as? Bool }
    func array(_ path: String) -> [Any] { (value(path) as? [Any]) ?? [] }
    func strings(_ path: String) -> [String] { array(path).compactMap { $0 as? String } }
}

/// A session plus helpers for building requests.
struct Client {
    let session = FacadeSession()
    static let defaultNow = "2026-11-02T04:30:00Z"

    func call(
        _ op: String, _ args: String = "{}", now: String = Client.defaultNow, zone: String = "Asia/Kolkata"
    ) async -> Reply {
        let request =
            "{\"op\":\"\(op)\",\"args\":\(args),\"ctx\":{\"now\":\"\(now)\",\"timeZone\":\"\(zone)\",\"locale\":\"en-IN\"}}"
        return Reply(await session.handle(Data(request.utf8)))
    }

    func raw(_ text: String) async -> Reply {
        Reply(await session.handle(Data(text.utf8)))
    }

    /// Household of `adults` + `children`, everybody answered "nobody avoids anything".
    @discardableResult
    func onboard(adults: Int = 2, children: Int = 1) async -> Reply {
        let created = await call("household.create", "{\"adults\":\(adults),\"children\":\(children)}")
        #expect(created.ok)
        let answered = await call("safety.confirmNobody", "{\"pendingItemCount\":0}")
        #expect(answered.ok)
        #expect(answered.string("gate.status") == "open")
        return answered
    }

    func restrictionIDs() async -> [String] {
        let catalog = await call("safety.catalog")
        return catalog.array("restrictions").compactMap { ($0 as? [String: Any])?["id"] as? String }
    }

    /// Generates the week and returns the plan id.
    func generate(absences: String = "[]") async -> (id: String, reply: Reply) {
        let reply = await call("plan.generate", "{\"absences\":\(absences)}")
        #expect(reply.ok, "plan.generate failed: \(reply.raw.prefix(300))")
        return (reply.string("plan.id") ?? "", reply)
    }

    func exportedPlans() async -> [[String: Any]] {
        let export = await call("state.export")
        return export.array("snapshot.mealPlans").compactMap { $0 as? [String: Any] }
    }

    func approve(_ planID: String) async -> Reply {
        let preview = await call("plan.approvalPreview", "{\"planId\":\"\(planID)\"}")
        guard preview.ok, let hash = preview.string("plan.contentHash") else { return preview }
        return await call(
            "plan.approve", "{\"planId\":\"\(planID)\",\"shownContentHash\":\"\(hash)\",\"gesture\":\"confirm-button\"}")
    }
}

func quoted(_ ids: [String]) -> String {
    "[" + ids.map { "\"\($0)\"" }.joined(separator: ",") + "]"
}

/// `{"restriction": id, "scope": {"kind":"household"}}` items for every id.
func householdItems(_ ids: [String]) -> String {
    "[" + ids.map { "{\"restriction\":\"\($0)\",\"scope\":{\"kind\":\"household\"}}" }.joined(separator: ",") + "]"
}
