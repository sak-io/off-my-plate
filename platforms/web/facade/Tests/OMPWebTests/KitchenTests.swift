import Foundation
import Testing

@testable import OMPWeb

/// W13: pantry, Mark cooked, shopping list, Notes import, learning and data operations, through the facade.
@Suite struct KitchenTests {
    func pantryAdd(_ client: Client, _ name: String = "Rice", quantity: String = "2", now: String = Client.defaultNow)
        async -> Reply
    {
        await client.call(
            "pantry.add",
            "{\"name\":\"\(name)\",\"quantity\":\(quantity),\"unit\":\"kg\",\"location\":\"shelf\"}", now: now)
    }

    func household(_ client: Client) async -> NSDictionary? {
        let export = await client.call("state.export")
        return ((export.json["result"] as? [String: Any])?["snapshot"] as? [String: Any])?["household"] as? NSDictionary
    }

    func snapshotArray(_ client: Client, _ key: String) async -> [Any] {
        await client.call("state.export").array("snapshot.\(key)")
    }

    // MARK: pantry

    @Test func pantryCrudRoundTrip() async {
        let client = Client()
        await client.onboard()
        let added = await pantryAdd(client)
        #expect(added.ok, "\(added.raw.prefix(300))")
        let id = added.string("item.item.id") ?? ""
        #expect(!id.isEmpty)
        #expect(added.string("item.confidence") == "confident")
        #expect((await client.call("pantry.list")).array("items").count == 1)
        let updated = await client.call(
            "pantry.update",
            "{\"itemId\":\"\(id)\",\"name\":\"Rice\",\"quantity\":5,\"unit\":\"kg\",\"location\":\"fridge\"}")
        #expect(updated.ok)
        #expect(updated.string("item.item.location") == "fridge")
        #expect((await client.call("pantry.reconfirm", "{\"itemId\":\"\(id)\"}")).ok)
        #expect((await client.call("pantry.delete", "{\"itemId\":\"\(id)\"}")).ok)
        #expect((await client.call("pantry.list")).array("items").isEmpty)
        #expect((await client.call("pantry.delete", "{\"itemId\":\"\(id)\"}")).code == "pantry_item_not_found")
        #expect((await client.call("pantry.reconfirm", "{\"itemId\":\"nope\"}")).code == "pantry_item_not_found")
    }

    @Test func pantryConfidenceDropsWhenNotReconfirmed() async {
        let client = Client()
        await client.onboard()
        let added = await pantryAdd(client)
        #expect(added.ok)
        let later = await client.call("pantry.list", "{}", now: "2027-02-15T04:30:00Z")
        #expect(later.string("items.0.confidence") == "low")
    }

    @Test func pantrySearchFindsIngredientsAndResolveWorks() async {
        let client = Client()
        await client.onboard()
        let found = await client.call("pantry.search", "{\"query\":\"onion\"}")
        #expect(found.ok)
        let ingredient = found.string("candidates.0.ingredientId") ?? ""
        #expect(!ingredient.isEmpty)
        let free = await pantryAdd(client, "mystery tin")
        let id = free.string("item.item.id") ?? ""
        let resolved = await client.call("pantry.resolve", "{\"itemId\":\"\(id)\",\"ingredientId\":\"\(ingredient)\"}")
        #expect(resolved.ok, "\(resolved.raw.prefix(300))")
        let unknown = await client.call("pantry.resolve", "{\"itemId\":\"\(id)\",\"ingredientId\":\"no-such\"}")
        #expect(unknown.code == "unknown_ingredient")
    }

    @Test func pantryInputsAreBounded() async {
        let client = Client()
        await client.onboard()
        for quantity in ["1e30", "-1", "9223372036854775807", "-9223372036854775808", "1000000001"] {
            let reply = await pantryAdd(client, "Rice", quantity: quantity)
            #expect(reply.code == "invalid_input", "quantity \(quantity): \(reply.raw.prefix(200))")
        }
        #expect((await pantryAdd(client, "Rice", quantity: "1000000000")).ok)
        #expect((await pantryAdd(client, "Rice", quantity: "0")).ok)
        #expect((await pantryAdd(client, String(repeating: "x", count: 201))).code == "invalid_input")
        #expect((await pantryAdd(client, "   ")).code == "invalid_input")
        let expiry = await client.call(
            "pantry.add",
            "{\"name\":\"Milk\",\"quantity\":1,\"unit\":\"l\",\"location\":\"fridge\",\"expiresOn\":\"9999-12-31\"}")
        #expect(expiry.code == "invalid_input")
        let badUnit = await client.call(
            "pantry.add", "{\"name\":\"Milk\",\"quantity\":1,\"unit\":\"bucket\",\"location\":\"fridge\"}")
        #expect(badUnit.code == "bad_request")
        for limit in ["9223372036854775807", "-9223372036854775808", "0", "-5", "21"] {
            let reply = await client.call("pantry.search", "{\"query\":\"rice\",\"limit\":\(limit)}")
            #expect(reply.ok, "limit \(limit)")
            #expect(reply.array("candidates").count <= 20)
        }
        #expect((await client.call("pantry.search", "{\"query\":\"\(String(repeating: "q", count: 201))\"}")).code == "invalid_input")
        // Nothing but the two accepted items was stored.
        #expect((await client.call("pantry.list")).array("items").count == 2)
    }

    // MARK: Mark cooked

    @Test func markCookedIsRefusedForADraftAndAllowedOnceApproved() async throws {
        let client = Client()
        await client.onboard()
        let plan = await client.generate()
        let meal = plan.reply.string("plan.meals.0.id") ?? ""
        let args = "{\"planId\":\"\(plan.id)\",\"mealId\":\"\(meal)\"}"
        let draftPropose = await client.call("cook.propose", args)
        #expect(draftPropose.code == "mark_cooked")
        #expect(draftPropose.raw.contains("planNotApproved"))
        let draftMark = await client.call("cook.mark", args)
        #expect(draftMark.code == "mark_cooked")
        #expect((await snapshotArray(client, "cookLogs")).isEmpty)

        #expect((await client.approve(plan.id)).ok)
        let proposal = await client.call("cook.propose", args)
        #expect(proposal.ok, "\(proposal.raw.prefix(300))")
        let marked = await client.call("cook.mark", args)
        #expect(marked.ok, "\(marked.raw.prefix(300))")
        #expect(marked.string("plan.plan.status") == "approved")
        #expect(marked.bool("plan.effectivelyApproved") == true)
        #expect((await snapshotArray(client, "cookLogs")).count == 1)
        let again = await client.call("cook.mark", args)
        #expect(again.code == "mark_cooked")
        #expect(again.raw.contains("alreadyCooked"))
        #expect((await snapshotArray(client, "cookLogs")).count == 1)
    }

    @Test func markCookedRejectsUnboundedOrUnknownAmounts() async {
        let client = Client()
        await client.onboard()
        let plan = await client.generate()
        let meal = plan.reply.string("plan.meals.0.id") ?? ""
        #expect((await client.approve(plan.id)).ok)
        let base = "\"planId\":\"\(plan.id)\",\"mealId\":\"\(meal)\""
        let huge = await client.call("cook.mark", "{\(base),\"amounts\":[{\"ingredientId\":\"onion\",\"amount\":1e30,\"unit\":\"g\"}]}")
        #expect(huge.code == "invalid_input" || huge.code == "unknown_ingredient")
        let many = Array(repeating: "{\"ingredientId\":\"onion\",\"amount\":1,\"unit\":\"g\"}", count: 201).joined(separator: ",")
        #expect((await client.call("cook.mark", "{\(base),\"amounts\":[\(many)]}")).code == "invalid_input")
        let unknown = await client.call("cook.mark", "{\(base),\"amounts\":[{\"ingredientId\":\"no-such\",\"amount\":1,\"unit\":\"g\"}]}")
        #expect(unknown.code == "unknown_ingredient")
        #expect((await snapshotArray(client, "cookLogs")).isEmpty)
    }

    @Test func aMealBlockedBySafetyCannotBeMarkedCooked() async {
        let client = Client()
        await client.onboard()
        let plan = await client.generate()
        #expect((await client.approve(plan.id)).ok)
        // A rule added after approval flags meals that break it; blocked meals are not cookable.
        let all = await client.restrictionIDs()
        let items = householdItems(all)
        let added = await client.call("safety.confirm", "{\"items\":\(items)}")
        let blocked = added.strings("recheck.blockedMealIds")
        #expect(!blocked.isEmpty, "adding every restriction should flag meals of the approved plan")
        let reply = await client.call("cook.mark", "{\"planId\":\"\(plan.id)\",\"mealId\":\"\(blocked.first ?? "")\"}")
        #expect(reply.code == "mark_cooked")
    }

    // MARK: shopping

    @Test func shoppingListFlow() async {
        let client = Client()
        await client.onboard()
        let plan = await client.generate()
        #expect((await client.approve(plan.id)).ok)
        #expect((await client.call("shopping.refresh")).ok)
        let added = await client.call("shopping.add", "{\"name\":\"Bananas\",\"quantity\":6,\"unit\":\"piece\"}")
        #expect(added.ok, "\(added.raw.prefix(300))")
        let id = added.string("item.id") ?? ""
        #expect(added.string("item.origin") == "manual")
        let shared = await client.call("shopping.shareText")
        #expect(shared.string("text")?.contains("Banana") == true)
        let checked = await client.call("shopping.check", "{\"itemId\":\"\(id)\",\"checked\":true}")
        #expect(checked.bool("item.checkedOff") == true)
        let bought = await client.call("shopping.boughtEverything")
        #expect(bought.ok, "\(bought.raw.prefix(300))")
        let remaining = (await client.call("shopping.list")).array("items").compactMap { ($0 as? [String: Any])?["id"] as? String }
        #expect(!remaining.contains(id))
        // A manual item can be removed; a missing one is reported.
        let second = await client.call("shopping.add", "{\"name\":\"Salt\"}")
        let secondID = second.string("item.id") ?? ""
        #expect((await client.call("shopping.remove", "{\"itemId\":\"\(secondID)\"}")).ok)
        #expect((await client.call("shopping.remove", "{\"itemId\":\"\(secondID)\"}")).code == "shopping_item_not_found")
    }

    @Test func shoppingInputsAreBounded() async {
        let client = Client()
        await client.onboard()
        for quantity in ["1e30", "-3", "9223372036854775807", "1000000001"] {
            let reply = await client.call("shopping.add", "{\"name\":\"Rice\",\"quantity\":\(quantity),\"unit\":\"kg\"}")
            #expect(reply.code == "invalid_input", "quantity \(quantity)")
        }
        #expect((await client.call("shopping.add", "{\"name\":\"\"}")).code == "invalid_input")
        #expect((await client.call("shopping.add", "{\"name\":\"x\",\"ingredientId\":\"no-such\"}")).code == "unknown_ingredient")
        #expect((await client.call("shopping.list")).array("items").isEmpty)
    }

    // MARK: Notes import

    @Test func importPreviewParsesPastedTextAndFileBytesAndSavesNothing() async {
        let client = Client()
        await client.onboard()
        let before = await client.call("state.export").raw
        let text = "2 kg onions\\n- [x] milk\\nCall the plumber tomorrow"
        let parsed = await client.call("import.parseText", "{\"text\":\"\(text)\"}")
        #expect(parsed.ok, "\(parsed.raw.prefix(300))")
        #expect(parsed.array("lines").count >= 2)
        #expect(parsed.string("lines.0.name")?.lowercased().contains("onion") == true)
        #expect(parsed.bool("truncated") == false)
        let bytes = Data("2 kg onions\nmilk\n".utf8).base64EncodedString()
        let file = await client.call("import.parseFile", "{\"base64\":\"\(bytes)\"}")
        #expect(file.ok)
        #expect(file.array("lines").count == 2)
        let bom = Data([0xEF, 0xBB, 0xBF] + Array("rice\n".utf8)).base64EncodedString()
        #expect((await client.call("import.parseFile", "{\"base64\":\"\(bom)\"}")).string("lines.0.name") == "rice")
        #expect((await client.call("state.export")).raw == before)
    }

    @Test func importRefusesBinaryOversizedAndMalformedInput() async {
        let client = Client()
        await client.onboard()
        let binary = Data([0x89, 0x50, 0x00, 0x47]).base64EncodedString()
        #expect((await client.call("import.parseFile", "{\"base64\":\"\(binary)\"}")).code == "not_text")
        let invalidUTF8 = Data([0xFF, 0xFE, 0xFD]).base64EncodedString()
        #expect((await client.call("import.parseFile", "{\"base64\":\"\(invalidUTF8)\"}")).code == "not_text")
        #expect((await client.call("import.parseFile", "{\"base64\":\"!!!\"}")).code == "invalid_input")
        let big = String(repeating: "A", count: Limits.maxBase64Characters + 4)
        #expect((await client.call("import.parseFile", "{\"base64\":\"\(big)\"}")).code == "invalid_input")
        let longText = String(repeating: "a", count: Limits.maxImportBytes + 1)
        #expect((await client.call("import.parseText", "{\"text\":\"\(longText)\"}")).code == "invalid_input")
        #expect((await client.call("import.confirm", "{\"destination\":\"shoppingList\",\"items\":[]}")).code == "invalid_input")
        #expect((await client.call("import.confirm", "{\"destination\":\"nowhere\",\"items\":[{\"name\":\"a\"}]}")).code == "bad_request")
        #expect((await client.call("import.confirm", "{\"destination\":\"pantry\",\"items\":[{\"name\":\" \"}]}")).code == "invalid_input")
        #expect(
            (await client.call("import.confirm", "{\"destination\":\"pantry\",\"items\":[{\"name\":\"a\",\"quantity\":1e30,\"unit\":\"g\"}]}")).code
                == "invalid_input")
        #expect(
            (await client.call("import.confirm", "{\"destination\":\"pantry\",\"items\":[{\"name\":\"a\",\"ingredientId\":\"no-such\"}]}")).code
                == "unknown_ingredient")
        let many = Array(repeating: "{\"name\":\"a\"}", count: 501).joined(separator: ",")
        #expect((await client.call("import.confirm", "{\"destination\":\"pantry\",\"items\":[\(many)]}")).code == "invalid_input")
        #expect((await client.call("shopping.list")).array("items").isEmpty)
        #expect((await client.call("pantry.list")).array("items").isEmpty)
    }

    @Test func importMergesIntoListAndPantryAndNeverTouchesRules() async {
        let client = Client()
        await client.onboard()
        let ids = await client.restrictionIDs()
        let rule = await client.call("safety.addRule", "{\"item\":{\"restriction\":\"\(ids[0])\",\"scope\":{\"kind\":\"household\"}}}")
        #expect(rule.ok)
        let before = await household(client)
        #expect(before != nil)

        let toList = await client.call(
            "import.confirm",
            "{\"destination\":\"shoppingList\",\"items\":[{\"name\":\"Lemons\",\"quantity\":4,\"unit\":\"piece\"},{\"name\":\"Lemons\",\"quantity\":2,\"unit\":\"piece\"}]}")
        #expect(toList.ok, "\(toList.raw.prefix(300))")
        #expect(toList.value("filesImported") as? Int == 1)
        #expect(toList.value("itemsTotal") as? Int == 2)
        #expect(toList.strings("destinations") == ["shoppingList"])
        let list = await client.call("shopping.list")
        #expect(list.array("items").count == 1)
        #expect(list.string("items.0.origin") == "notesImport")

        let toPantry = await client.call(
            "import.confirm", "{\"destination\":\"pantry\",\"items\":[{\"name\":\"Dal\",\"quantity\":500,\"unit\":\"g\"}]}")
        #expect(toPantry.ok)
        #expect((await client.call("pantry.list")).array("items").count == 1)

        let after = await household(client)
        #expect(after == before, "an import changed the household or its rules")
    }

    // MARK: learning and forgetting

    @Test func aForgottenFactStaysForgottenAcrossExportAndImport() async {
        let client = Client()
        await client.onboard()
        let found = await client.call("pantry.search", "{\"query\":\"onion\"}")
        let ingredient = found.string("candidates.0.ingredientId") ?? ""
        #expect(!ingredient.isEmpty)
        let body = "{\"destination\":\"shoppingList\",\"items\":[{\"name\":\"onion\",\"ingredientId\":\"\(ingredient)\"}]}"
        for now in ["2026-11-02T04:30:00Z", "2026-11-10T04:30:00Z", "2026-11-11T04:30:00Z"] {
            #expect((await client.call("import.confirm", body, now: now)).ok)
        }
        let later = "2026-11-12T04:30:00Z"
        #expect((await client.call("learning.refresh", "{}", now: later)).ok)
        let facts = await client.call("state.export", "{}", now: later).array("snapshot.facts")
        let factID = (facts.first as? [String: Any])?["id"] as? String ?? ""
        #expect(!factID.isEmpty, "three staple imports produced no fact")

        let forgotten = await client.call("learning.forget", "{\"factId\":\"\(factID)\"}", now: later)
        #expect(forgotten.ok, "\(forgotten.raw.prefix(300))")
        #expect(forgotten.string("fact.status") == "forgotten")
        #expect((await client.call("learning.forget", "{\"factId\":\"nope\"}", now: later)).code == "fact_not_found")
        let answerForgotten = await client.call("learning.confirm", "{\"factId\":\"\(factID)\"}", now: later)
        #expect(answerForgotten.code == "fact_not_open")

        func isListed(_ reply: Reply) -> Bool {
            reply.array("facts").contains { ($0 as? [String: Any])?["id"] as? String == factID }
        }
        let listed = await client.call("learning.list", "{}", now: later)
        #expect(!isListed(listed))
        let export = await client.call("state.export", "{}", now: later)
        let snapshot = export.value("snapshot") ?? [:]
        let restored = await Client().importSnapshot(snapshot, now: later)
        #expect(restored.0.ok, "\(restored.0.raw.prefix(300))")
        let refreshed = await restored.1.call("learning.refresh", "{}", now: later)
        #expect(refreshed.ok)
        #expect(!isListed(refreshed))
        let relisted = await restored.1.call("learning.list", "{}", now: "2026-12-20T04:30:00Z")
        #expect(relisted.ok)
        #expect(!isListed(relisted))
        let status = await restored.1.call("state.export", "{}", now: later).array("snapshot.facts")
            .compactMap { $0 as? [String: Any] }.first { $0["id"] as? String == factID }?["status"] as? String
        #expect(status == "forgotten")
    }

    @Test func learningRefusesUnknownFactsAndBadAnswers() async {
        let client = Client()
        await client.onboard()
        #expect((await client.call("learning.answer", "{\"factId\":\"nope\",\"answer\":\"yes\"}")).code == "fact_not_found")
        #expect((await client.call("learning.answer", "{\"factId\":\"nope\",\"answer\":\"maybe\"}")).code == "bad_request")
        #expect((await client.call("learning.reflectBack")).ok)
        #expect((await client.call("learning.list")).array("facts").isEmpty)
    }

    // MARK: data

    @Test func deleteAllLeavesEveryRepositoryEmpty() async {
        let client = Client()
        await client.onboard()
        let plan = await client.generate()
        #expect((await client.approve(plan.id)).ok)
        #expect((await pantryAdd(client)).ok)
        #expect((await client.call("shopping.add", "{\"name\":\"Salt\"}")).ok)
        #expect((await client.call("import.confirm", "{\"destination\":\"pantry\",\"items\":[{\"name\":\"Dal\"}]}")).ok)

        #expect((await client.call("data.deleteAll", "{}")).code == "bad_request")
        #expect((await client.call("data.deleteAll", "{\"confirmed\":false}")).code == "confirmation_required")
        #expect(!(await snapshotArray(client, "mealPlans")).isEmpty)

        // The clock may be anywhere: deleting is never blocked by clock_behind_state.
        let deleted = await client.call("data.deleteAll", "{\"confirmed\":true}", now: "2026-01-01T00:00:00Z")
        #expect(deleted.ok, "\(deleted.raw.prefix(300))")
        let export = await client.call("state.export")
        for key in ["mealPlans", "pantry", "shopping", "cookLogs", "facts", "learningEvents", "promptStates"] {
            #expect(export.array("snapshot.\(key)").isEmpty, "\(key) is not empty after delete all")
        }
        #expect(export.value("snapshot.household") == nil)
        #expect(export.value("snapshot.idCounter") as? Int == 0)
        #expect((await client.call("household.get")).string("gate.status") == "noHousehold")
        // A new household can be created afterwards.
        #expect((await client.call("household.create", "{\"adults\":1,\"children\":0}")).ok)
    }

    @Test func pruneReportsTheTwelveMonthCutoff() async {
        let client = Client()
        await client.onboard()
        let pruned = await client.call("data.prune")
        #expect(pruned.ok)
        #expect(pruned.string("cutoff") == "2025-11-02T04:30:00Z")
    }

    @Test func namesThatLookLikeDatesSurviveStateImport() async {
        let client = Client()
        await client.onboard()
        #expect((await pantryAdd(client, "abcd-ef-gh")).ok)
        #expect((await pantryAdd(client, "abcd-ef-ghTijklmnopqrs")).ok)
        let snapshot = await client.call("state.export").value("snapshot") ?? [:]
        let restored = await Client().importSnapshot(snapshot, now: Client.defaultNow)
        #expect(restored.0.ok, "\(restored.0.raw.prefix(300))")
        #expect((await restored.1.call("pantry.list")).array("items").count == 2)
    }

    @Test func absurdPantryAmountsInAStateFileAreRejected() async {
        let client = Client()
        await client.onboard()
        #expect((await pantryAdd(client)).ok)
        var snapshot = (await client.call("state.export").value("snapshot") as? [String: Any]) ?? [:]
        var pantry = (snapshot["pantry"] as? [[String: Any]]) ?? []
        pantry[0]["quantity"] = 1e30
        snapshot["pantry"] = pantry
        let restored = await Client().importSnapshot(snapshot, now: Client.defaultNow)
        #expect(restored.0.code == "invalid_state")
    }
}

extension Client {
    /// Imports `snapshot` into a NEW client's session and returns the reply with that client.
    func importSnapshot(_ snapshot: Any, now: String) async -> (Reply, Client) {
        let data = (try? JSONSerialization.data(withJSONObject: snapshot, options: [.sortedKeys])) ?? Data()
        let reply = await call("state.import", "{\"snapshot\":\(String(decoding: data, as: UTF8.self))}", now: now)
        return (reply, self)
    }
}
