import Foundation
import Testing

/// AC-2.x, AC-3.x, G3: the mandatory safety question, with the same rules as the iOS screen.
@Suite struct SafetyFlowTests {
    @Test func theCatalogOffersRestrictionChips() async {
        let ids = await Client().restrictionIDs()
        #expect(ids.count >= 5)
        #expect(Set(ids).count == ids.count)
    }

    @Test func parsingNeverSavesAnything() async {
        let c = Client()
        await c.call("household.create", "{\"adults\":1,\"children\":0}")
        let parsed = await c.call("safety.parse", "{\"text\":\"no peanuts and zzzfood\"}")
        #expect(parsed.ok)
        let kinds = parsed.array("candidates").compactMap { ($0 as? [String: Any])?["kind"] as? String }
        #expect(kinds.contains("restriction"))
        #expect(kinds.contains("unmapped"))
        let gate = await c.call("gate.status")
        #expect(gate.string("status") == "refused")
        let household = await c.call("household.get")
        #expect(household.array("household.rules").isEmpty)
    }

    @Test func unmappedItemsMustBeResolvedBeforeAnythingIsSaved() async {
        let c = Client()
        await c.call("household.create", "{\"adults\":2,\"children\":0}")
        let ids = await c.restrictionIDs()
        let reply = await c.call(
            "safety.confirm",
            "{\"items\":[{\"restriction\":\"\(ids[0])\"},{\"unresolvedText\":\"zzzfood\",\"scope\":{\"kind\":\"household\"}}]}")
        #expect(reply.code == "unresolved_items")
        let after = await c.call("household.get")
        #expect(after.array("household.rules").isEmpty)
        #expect(after.string("gate.status") == "refused")
        // Both fields at once is a malformed item, not a way around the rule.
        let both = await c.call(
            "safety.confirm", "{\"items\":[{\"restriction\":\"\(ids[0])\",\"unresolvedText\":\"x\"}]}")
        #expect(both.code == "invalid_input")
        #expect((await c.call("household.get")).array("household.rules").isEmpty)
    }

    @Test func confirmingNeedsAtLeastOneItem() async {
        let c = Client()
        await c.call("household.create", "{\"adults\":1,\"children\":0}")
        #expect((await c.call("safety.confirm", "{\"items\":[]}")).code == "no_items")
        #expect((await c.call("safety.confirm", "{}")).code == "bad_request")
        #expect((await c.call("gate.status")).string("status") == "refused")
    }

    @Test func nobodyIsOnlyAllowedWhileTheListIsEmpty() async {
        let c = Client()
        await c.call("household.create", "{\"adults\":2,\"children\":0}")
        let refused = await c.call("safety.confirmNobody", "{\"pendingItemCount\":1}")
        #expect(refused.code == "nobody_not_allowed")
        #expect((await c.call("safety.confirmNobody")).code == "bad_request")
        #expect((await c.call("gate.status")).string("status") == "refused")
        #expect((await c.call("safety.confirmNobody", "{\"pendingItemCount\":0}")).string("gate.status") == "open")
    }

    @Test func nobodyContradictingStoredRulesIsRefused() async {
        let c = Client()
        await c.call("household.create", "{\"adults\":2,\"children\":0}")
        let ids = await c.restrictionIDs()
        let saved = await c.call("safety.confirm", "{\"items\":\(householdItems([ids[0]]))}")
        #expect(saved.ok)
        #expect(saved.string("gate.status") == "open")
        #expect(saved.array("household.rules").count == 1)
        let nobody = await c.call("safety.confirmNobody", "{\"pendingItemCount\":0}")
        #expect(nobody.code == "safety_transition")
    }

    @Test func rulesAreBuiltFromTheCatalogOnly() async {
        let c = Client()
        await c.call("household.create", "{\"adults\":1,\"children\":0}")
        let reply = await c.call("safety.confirm", "{\"items\":[{\"restriction\":\"not-in-catalog\"}]}")
        #expect(reply.code == "unknown_restriction")
        // A caller-supplied tag set is not even a field.
        let sneaky = await c.call(
            "safety.confirm", "{\"items\":[{\"restriction\":\"x\",\"excludedTags\":[]}]}")
        #expect(!sneaky.ok)
        #expect((await c.call("household.get")).array("household.rules").isEmpty)
    }

    @Test func removingARuleNeedsConfirmation() async {
        let c = Client()
        await c.call("household.create", "{\"adults\":1,\"children\":0}")
        let ids = await c.restrictionIDs()
        let saved = await c.call("safety.confirm", "{\"items\":\(householdItems([ids[0]]))}")
        let ruleID = saved.string("household.rules.0.id") ?? ""
        #expect(!ruleID.isEmpty)
        #expect((await c.call("safety.removeRule", "{\"ruleId\":\"\(ruleID)\",\"confirmed\":false}")).code == "confirmation_required")
        #expect((await c.call("safety.removeRule", "{\"ruleId\":\"\(ruleID)\"}")).code == "bad_request")
        #expect((await c.call("household.get")).array("household.rules").count == 1)
        let removed = await c.call("safety.removeRule", "{\"ruleId\":\"\(ruleID)\",\"confirmed\":true}")
        #expect(removed.ok)
        #expect(removed.array("household.rules").isEmpty)
    }

    @Test func aMemberAnswerAddsTheirRulesThenConfirms() async {
        let c = Client()
        await c.onboard(adults: 1, children: 0)
        let added = await c.call("household.addMember", "{\"role\":\"child\"}")
        let member = c.lastMember(added)
        let ids = await c.restrictionIDs()
        let unresolved = await c.call(
            "safety.confirmMember", "{\"memberId\":\"\(member)\",\"items\":[{\"unresolvedText\":\"zzz\"}]}")
        #expect(unresolved.code == "unresolved_items")
        #expect((await c.call("gate.status")).string("status") == "refused")
        let done = await c.call(
            "safety.confirmMember", "{\"memberId\":\"\(member)\",\"items\":[{\"restriction\":\"\(ids[0])\"}]}")
        #expect(done.ok, "confirmMember failed: \(done.raw.prefix(300))")
        #expect(done.string("gate.status") == "open")
        #expect(done.array("household.rules").count == 1)
    }
}
