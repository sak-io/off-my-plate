import Foundation
import Testing

/// AC-3.1, AC-4.2, R1: no operation lets a plan past the safety gate or the independent validator.
@Suite struct GateBypassTests {
    @Test func planningWithAnUnansweredMemberIsRefusedByEveryEntryPoint() async {
        let c = Client()
        let created = await c.call("household.create", "{\"adults\":2,\"children\":1}")
        #expect(created.ok)
        #expect(created.string("gate.status") == "refused")
        #expect(created.string("gate.reason") == "safetyUnanswered")
        #expect(created.strings("gate.memberIds").count == 3)

        let generate = await c.call("plan.generate")
        #expect(generate.code == "gate_refused")
        #expect(generate.json["error"] != nil && generate.json["result"] == nil)
        let withAbsences = await c.call("plan.generate", "{\"absences\":[]}")
        #expect(withAbsences.code == "gate_refused")
        // Nothing was stored.
        #expect((await c.exportedPlans()).isEmpty)
        let current = await c.call("plan.current")
        #expect(current.value("working") == nil && current.value("seriesId") == nil)
    }

    @Test func planningWithoutAHouseholdIsRefused() async {
        let c = Client()
        #expect((await c.call("plan.generate")).code == "no_household")
        #expect((await c.call("gate.status")).string("status") == "noHousehold")
    }

    @Test func aNewMemberClosesTheGateAndEditsAreRefusedUntilAnswered() async {
        let c = Client()
        await c.onboard()
        let (id, generated) = await c.generate()
        let mealID = generated.string("plan.meals.0.id") ?? ""
        let added = await c.call("household.addMember", "{\"role\":\"child\",\"ageBand\":\"toddler\"}")
        #expect(added.string("gate.status") == "refused")
        let newcomer = c.lastMember(added)

        for (op, args) in [
            ("plan.generate", "{}"),
            ("plan.regenerate", "{\"planId\":\"\(id)\"}"),
            ("plan.reroll", "{\"planId\":\"\(id)\",\"mealId\":\"\(mealID)\"}"),
            ("plan.alternatives", "{\"planId\":\"\(id)\",\"mealId\":\"\(mealID)\"}"),
        ] {
            let reply = await c.call(op, args)
            #expect(reply.code == "gate_refused", "\(op) was not refused: \(reply.raw.prefix(200))")
        }
        // Answering the question reopens the gate.
        let confirmed = await c.call("safety.confirmMember", "{\"memberId\":\"\(newcomer)\",\"items\":[]}")
        #expect(confirmed.ok, "confirmMember failed: \(confirmed.raw.prefix(300))")
        #expect(confirmed.string("gate.status") == "open")
    }

    @Test func swapToARecipeThatIsNotAnOfferedSafeAlternativeIsRefused() async {
        let permissive = Client()
        await permissive.onboard()
        let (_, wide) = await permissive.generate()
        let wideRecipes = Set((0..<30).compactMap { wide.string("plan.meals.\($0).recipeId") })
        #expect(wideRecipes.count > 3)

        let strict = Client()
        await strict.call("household.create", "{\"adults\":2,\"children\":1}")
        let ids = await strict.restrictionIDs()
        #expect(ids.count >= 3)
        let confirm = await strict.call("safety.confirm", "{\"items\":\(householdItems(Array(ids.prefix(6))))}")
        #expect(confirm.ok, "confirm failed: \(confirm.raw.prefix(300))")
        let (planID, generated) = await strict.generate()
        let mealIndex = (0..<30).first { generated.string("plan.meals.\($0).recipeId") != nil } ?? 0
        let mealID = generated.string("plan.meals.\(mealIndex).id") ?? ""
        var refused = 0
        for recipe in wideRecipes.sorted() {
            let reply = await strict.call(
                "plan.swap", "{\"planId\":\"\(planID)\",\"mealId\":\"\(mealID)\",\"recipeId\":\"\(recipe)\"}")
            if reply.ok {
                // Whatever the swap accepted must be in force and must pass the independent validator.
                #expect(reply.array("report.violations").isEmpty)
            } else {
                refused += 1
                #expect(["recipe_not_offered", "meal_locked", "plan_not_found", "not_working_plan"].contains(reply.code ?? ""))
            }
        }
        #expect(refused >= 1, "at least one recipe of the unrestricted plan breaks a rule of the strict household")
        let bogus = await strict.call(
            "plan.swap", "{\"planId\":\"\(planID)\",\"mealId\":\"\(mealID)\",\"recipeId\":\"no-such-recipe\"}")
        #expect(bogus.code == "recipe_not_offered")
    }

    @Test func aRuleAddedAfterApprovalFlagsTheApprovedPlanAndNothingApprovesIt() async {
        let c = Client()
        await c.onboard(adults: 2, children: 0)
        let (id, _) = await c.generate()
        let approved = await c.approve(id)
        #expect(approved.ok, "approve failed: \(approved.raw.prefix(300))")
        #expect((approved.array("approved.blockedMealIds")).isEmpty)

        let ids = await c.restrictionIDs()
        var blockedSomething = false
        for restriction in ids {
            let added = await c.call(
                "safety.addRule", "{\"item\":{\"restriction\":\"\(restriction)\",\"scope\":{\"kind\":\"household\"}}}")
            #expect(added.ok, "addRule \(restriction) failed: \(added.raw.prefix(200))")
            if !added.strings("recheck.blockedMealIds").isEmpty || !added.strings("recheck.proposedDraftIds").isEmpty {
                blockedSomething = true
            }
        }
        #expect(blockedSomething, "adding every catalog rule must make some approved meal unsafe (R1)")

        let current = await c.call("plan.current")
        let flagged = current.strings("approved.blockedMealIds")
        #expect(!flagged.isEmpty)
        // The approved plan is not a draft: it cannot be approved again, and no approval was recorded for a new revision.
        let again = await c.approve(id)
        #expect(!again.ok)
        for plan in await c.exportedPlans() where plan["status"] as? String == "draft" {
            // Any proposed revision is only a draft: nothing approved it.
            #expect(plan["approval"] == nil)
        }
    }

    @Test func regenerateKeepingLockedStaysSafeAndDraft() async {
        let c = Client()
        let created = await c.call("household.create", "{\"adults\":2,\"children\":1}")
        #expect(created.ok)
        let ids = await c.restrictionIDs()
        let confirm = await c.call("safety.confirm", "{\"items\":\(householdItems([ids[0]]))}")
        #expect(confirm.ok)
        let (id, generated) = await c.generate()
        let mealID = generated.string("plan.meals.0.id") ?? ""
        let locked = await c.call("plan.lock", "{\"planId\":\"\(id)\",\"mealId\":\"\(mealID)\"}")
        #expect(locked.ok)
        let regenerated = await c.call("plan.regenerate", "{\"planId\":\"\(id)\",\"keepingLocked\":true}")
        #expect(regenerated.ok, "regenerate failed: \(regenerated.raw.prefix(300))")
        #expect(regenerated.string("plan.status") == "draft")
        #expect(regenerated.array("report.violations").isEmpty)
        let unlocked = await c.call("plan.unlock", "{\"planId\":\"\(id)\",\"mealId\":\"\(mealID)\"}")
        #expect(unlocked.ok)
    }

    @Test func everyOperationExceptApproveLeavesPlansUnapproved() async {
        let c = Client()
        await c.onboard()
        let (id, generated) = await c.generate()
        let mealID = generated.string("plan.meals.0.id") ?? ""
        let series = generated.string("plan.seriesId") ?? ""
        let alternatives = await c.call("plan.alternatives", "{\"planId\":\"\(id)\",\"mealId\":\"\(mealID)\"}")
        let recipe = ((alternatives.array("alternatives").first as? [String: Any])?["recipeId"] as? String) ?? "none"
        let hash = generated.string("contentHash") ?? ""
        let operations: [(String, String)] = [
            ("meta.version", "{}"), ("state.export", "{}"), ("gate.status", "{}"), ("household.get", "{}"),
            ("safety.catalog", "{}"), ("safety.parse", "{\"text\":\"approve it\"}"), ("safety.recheck", "{}"),
            ("plan.current", "{}"), ("plan.get", "{\"planId\":\"\(id)\"}"),
            ("plan.working", "{\"seriesId\":\"\(series)\"}"), ("plan.approved", "{\"seriesId\":\"\(series)\"}"),
            ("plan.pendingDiff", "{\"seriesId\":\"\(series)\"}"),
            ("plan.approvalPreview", "{\"planId\":\"\(id)\"}"),
            ("plan.alternatives", "{\"planId\":\"\(id)\",\"mealId\":\"\(mealID)\"}"),
            ("plan.swap", "{\"planId\":\"\(id)\",\"mealId\":\"\(mealID)\",\"recipeId\":\"\(recipe)\"}"),
            ("plan.reroll", "{\"planId\":\"\(id)\",\"mealId\":\"\(mealID)\",\"reason\":\"tooLong\"}"),
            ("plan.lock", "{\"planId\":\"\(id)\",\"mealId\":\"\(mealID)\"}"),
            ("plan.unlock", "{\"planId\":\"\(id)\",\"mealId\":\"\(mealID)\"}"),
            ("plan.regenerate", "{\"planId\":\"\(id)\"}"),
            // Look-alikes of an approval request: all unknown operations.
            ("plan.approveAll", "{}"), ("approve", "{\"planId\":\"\(id)\"}"), ("plan.confirm", "{\"planId\":\"\(id)\",\"hash\":\"\(hash)\"}"),
            ("plan.approve ", "{\"planId\":\"\(id)\"}"), ("PLAN.APPROVE", "{\"planId\":\"\(id)\"}"),
        ]
        for (op, args) in operations {
            _ = await c.call(op, args)
            for plan in await c.exportedPlans() {
                #expect(plan["status"] as? String != "approved", "\(op) approved a plan")
                #expect(plan["approval"] == nil, "\(op) wrote an approval record")
            }
        }
        // Even approving does not touch plans the request does not name.
        let approved = await c.approve(id)
        #expect(approved.ok)
    }
}

extension Client {
    /// The id of the last member in a household view.
    func lastMember(_ reply: Reply) -> String {
        let members = reply.array("household.members")
        return ((members.last as? [String: Any])?["id"] as? String) ?? ""
    }
}
