import Foundation
import OMPDomain

// Domain <-> record mappers (ADR 0003). `apply` writes a domain value into a record and throws
// for an empty id or unencodable content; it may leave the record half-written when it throws,
// so repositories run it inside `ModelContext.commit`, which rolls back. `domain()` reads a
// record back and throws for any stored value it cannot map. Round trips are tested in
// `MapperRoundTripTests`.
//
// `MealPlan.status` and `MealPlan.approval` have `package` setters in OMPDomain; this module is
// in another package, so plans are rebuilt through the public memberwise initialiser.

// MARK: Household (scalar columns; members and rules are child records, see the repository)

extension HouseholdRecord {
    static let mappingName = "Household"

    func apply(_ household: Household) throws {
        id = try Mapping.raw(household.id, entity: Self.mappingName)
        snacksEnabled = household.settings.snacksEnabled
        weekStartsOn = household.settings.weekStartsOn.rawValue
        createdAt = household.createdAt
        updatedAt = household.updatedAt
        deletedAt = nil
    }

    func domain(members: [Member], rules: [Rule]) throws -> Household {
        Household(
            id: try Mapping.entityID(id, entity: Self.mappingName),
            members: members,
            rules: rules,
            settings: HouseholdSettings(
                snacksEnabled: snacksEnabled,
                weekStartsOn: try Mapping.value(Weekday.self, weekStartsOn, entity: Self.mappingName, field: "weekStartsOn")),
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

// MARK: Member

extension MemberRecord {
    static let mappingName = "Member"

    func apply(_ member: Member, sortIndex: Int) throws {
        id = try Mapping.raw(member.id, entity: Self.mappingName)
        self.sortIndex = sortIndex
        labelRole = member.label.role.rawValue
        labelNumber = member.label.number
        name = member.name
        ageBand = member.ageBand?.rawValue
        safetyStatus = member.safetyStatus.rawValue
        safetyConfirmedAt = member.safetyConfirmedAt
        needsSchoolLunch = member.needsSchoolLunch
        schoolDays = Mapping.sortedRaw(member.schoolDays)
        portionOverride = member.portionOverride
        deletedAt = member.deletedAt
    }

    func domain() throws -> Member {
        Member(
            id: try Mapping.entityID(id, entity: Self.mappingName),
            label: MemberLabel(
                role: try Mapping.value(MemberRole.self, labelRole, entity: Self.mappingName, field: "labelRole"),
                number: labelNumber),
            name: name,
            ageBand: try Mapping.optionalValue(AgeBand.self, ageBand, entity: Self.mappingName, field: "ageBand"),
            safetyStatus: try Mapping.value(
                SafetyStatus.self, safetyStatus, entity: Self.mappingName, field: "safetyStatus"),
            safetyConfirmedAt: safetyConfirmedAt,
            needsSchoolLunch: needsSchoolLunch,
            schoolDays: Set(try schoolDays.map {
                try Mapping.value(Weekday.self, $0, entity: Self.mappingName, field: "schoolDays")
            }),
            portionOverride: portionOverride,
            deletedAt: deletedAt
        )
    }
}

// MARK: Rule

extension RuleRecord {
    static let mappingName = "Rule"

    func apply(_ rule: Rule, sortIndex: Int) throws {
        id = try Mapping.raw(rule.id, entity: Self.mappingName)
        let memberId: String?
        switch rule.scope {
        case .household:
            memberId = nil
        case .member(let id):
            memberId = try Mapping.raw(id, entity: Self.mappingName)
        }
        let restrictionId = try Mapping.raw(rule.restriction, entity: Self.mappingName)

        self.sortIndex = sortIndex
        kind = rule.kind.rawValue
        scopeKind = memberId == nil ? "household" : "member"
        scopeMemberId = memberId
        restriction = restrictionId
        excludedTags = Mapping.sortedRaw(rule.excludedTags)
        source = rule.source.rawValue
        createdAt = rule.createdAt
    }

    func domain() throws -> Rule {
        let scope: RuleScope
        switch scopeKind {
        case "household":
            scope = .household
        case "member":
            scope = .member(try Mapping.entityID(scopeMemberId ?? "", entity: Self.mappingName))
        default:
            throw PersistenceError.invalidValue(entity: Self.mappingName, field: "scopeKind", value: scopeKind)
        }
        return Rule(
            id: try Mapping.entityID(id, entity: Self.mappingName),
            kind: try Mapping.value(RuleKind.self, kind, entity: Self.mappingName, field: "kind"),
            scope: scope,
            restriction: try Mapping.entityID(restriction, entity: Self.mappingName),
            excludedTags: Set(try excludedTags.map {
                try Mapping.value(FoodTag.self, $0, entity: Self.mappingName, field: "excludedTags")
            }),
            source: try Mapping.value(RuleSource.self, source, entity: Self.mappingName, field: "source"),
            createdAt: createdAt
        )
    }
}

// MARK: MealPlan

extension MealPlanRecord {
    static let mappingName = "MealPlan"

    func apply(_ plan: MealPlan) throws {
        let planId = try Mapping.raw(plan.id, entity: Self.mappingName)
        let series = try Mapping.raw(plan.seriesId, entity: Self.mappingName)
        let based = try plan.basedOn.map { try Mapping.raw($0, entity: Self.mappingName) }
        let blob = try PlanContentDTO.encode(plan.meals)

        id = planId
        seriesId = series
        revision = plan.revision
        basedOn = based
        weekStart = plan.weekStart.isoString
        status = plan.status.rawValue
        approvalApprover = plan.approval?.approver.rawValue
        approvalApprovedAt = plan.approval?.approvedAt
        approvalContentHash = plan.approval?.contentHash
        contentVersion = plan.contentVersion
        content = blob
        createdAt = plan.createdAt
    }

    func domain() throws -> MealPlan {
        let approval: PlanApproval?
        switch (approvalApprover, approvalApprovedAt, approvalContentHash) {
        case (nil, nil, nil):
            approval = nil
        case let (approver?, approvedAt?, contentHash?):
            approval = PlanApproval(
                approver: try Mapping.value(Approver.self, approver, entity: Self.mappingName, field: "approvalApprover"),
                approvedAt: approvedAt,
                contentHash: contentHash)
        default:
            throw PersistenceError.incompleteApproval(planId: id)
        }
        return MealPlan(
            id: try Mapping.entityID(id, entity: Self.mappingName),
            seriesId: try Mapping.entityID(seriesId, entity: Self.mappingName),
            revision: revision,
            basedOn: try Mapping.optionalEntityID(basedOn, entity: Self.mappingName),
            weekStart: try Mapping.localDate(weekStart, entity: Self.mappingName, field: "weekStart"),
            status: try Mapping.value(PlanStatus.self, status, entity: Self.mappingName, field: "status"),
            meals: try PlanContentDTO.decodeMeals(from: content, planId: id),
            approval: approval,
            contentVersion: contentVersion,
            createdAt: createdAt
        )
    }
}

// MARK: PantryItem

extension PantryItemRecord {
    static let mappingName = "PantryItem"

    func apply(_ item: PantryItem) throws {
        id = try Mapping.raw(item.id, entity: Self.mappingName)
        switch item.item {
        case .ingredient(let ingredient):
            ingredientId = try Mapping.raw(ingredient, entity: Self.mappingName)
            freeText = nil
        case .freeText(let text):
            ingredientId = nil
            freeText = text
        }
        quantity = item.quantity
        unit = item.unit.rawValue
        location = item.location.rawValue
        purchasedAt = item.purchasedAt
        expiresOn = item.expiresOn?.isoString
        lastConfirmedAt = item.lastConfirmedAt
        source = item.source.rawValue
    }

    func domain() throws -> PantryItem {
        let ref: PantryItemRef
        switch (ingredientId, freeText) {
        case (.some(let ingredient), .none):
            ref = .ingredient(try Mapping.entityID(ingredient, entity: Self.mappingName))
        case (.none, .some(let text)):
            ref = .freeText(text)
        default:
            throw PersistenceError.invalidValue(
                entity: Self.mappingName, field: "item", value: "needs exactly one of ingredientId, freeText")
        }
        return PantryItem(
            id: try Mapping.entityID(id, entity: Self.mappingName),
            item: ref,
            quantity: quantity,
            unit: try Mapping.value(MeasureUnit.self, unit, entity: Self.mappingName, field: "unit"),
            location: try Mapping.value(StorageLocation.self, location, entity: Self.mappingName, field: "location"),
            purchasedAt: purchasedAt,
            expiresOn: try Mapping.optionalLocalDate(expiresOn, entity: Self.mappingName, field: "expiresOn"),
            lastConfirmedAt: lastConfirmedAt,
            source: try Mapping.value(PantryItemSource.self, source, entity: Self.mappingName, field: "source")
        )
    }
}

// MARK: ShoppingItem

extension ShoppingItemRecord {
    static let mappingName = "ShoppingItem"

    func apply(_ item: ShoppingItem) throws {
        id = try Mapping.raw(item.id, entity: Self.mappingName)
        let ingredient = try item.ingredientId.map { try Mapping.raw($0, entity: Self.mappingName) }
        key = item.key
        ingredientId = ingredient
        name = item.name
        quantity = item.quantity
        unit = item.unit?.rawValue
        aisle = item.aisle.rawValue
        checkedOff = item.checkedOff
        origin = item.origin.rawValue
        group = item.group.rawValue
    }

    func domain() throws -> ShoppingItem {
        ShoppingItem(
            id: try Mapping.entityID(id, entity: Self.mappingName),
            key: key,
            ingredientId: try Mapping.optionalEntityID(ingredientId, entity: Self.mappingName),
            name: name,
            quantity: quantity,
            unit: try Mapping.optionalValue(MeasureUnit.self, unit, entity: Self.mappingName, field: "unit"),
            aisle: try Mapping.value(Aisle.self, aisle, entity: Self.mappingName, field: "aisle"),
            checkedOff: checkedOff,
            origin: try Mapping.value(ShoppingItemOrigin.self, origin, entity: Self.mappingName, field: "origin"),
            group: try Mapping.value(ShoppingItemGroup.self, group, entity: Self.mappingName, field: "group")
        )
    }
}

// MARK: CookLog

extension CookLogRecord {
    static let mappingName = "CookLog"

    func apply(_ log: CookLog) throws {
        let logId = try Mapping.raw(log.id, entity: Self.mappingName)
        let plan = try Mapping.raw(log.planId, entity: Self.mappingName)
        let meal = try Mapping.raw(log.mealId, entity: Self.mappingName)
        let recipe = try Mapping.raw(log.recipeId, entity: Self.mappingName)
        let blob = try PantryDeductionsDTO.encode(log.deductions)

        id = logId
        planId = plan
        mealId = meal
        recipeId = recipe
        cookedAt = log.cookedAt
        deductions = blob
    }

    func domain() throws -> CookLog {
        CookLog(
            id: try Mapping.entityID(id, entity: Self.mappingName),
            planId: try Mapping.entityID(planId, entity: Self.mappingName),
            mealId: try Mapping.entityID(mealId, entity: Self.mappingName),
            recipeId: try Mapping.entityID(recipeId, entity: Self.mappingName),
            cookedAt: cookedAt,
            deductions: try PantryDeductionsDTO.decode(from: deductions, cookLogId: id)
        )
    }
}

// MARK: Fact

extension FactRecord {
    static let mappingName = "Fact"

    func apply(_ fact: Fact) throws {
        let factId = try Mapping.raw(fact.id, entity: Self.mappingName)
        let columns = try FactKeyColumns(subject: fact.subject, statement: fact.statement, entity: Self.mappingName)

        id = factId
        subjectKind = columns.subjectKind
        subjectMemberId = columns.subjectMemberId
        statementKind = columns.statementKind
        statementRef = columns.statementRef
        origin = fact.origin.rawValue
        confidence = fact.confidence
        status = fact.status.rawValue
        suppressed = fact.suppressed
        forgottenAt = fact.forgottenAt
        createdAt = fact.createdAt
        updatedAt = fact.updatedAt
    }

    func domain() throws -> Fact {
        let columns = FactKeyColumns(
            subjectKind: subjectKind, subjectMemberId: subjectMemberId, statementKind: statementKind,
            statementRef: statementRef)
        return Fact(
            id: try Mapping.entityID(id, entity: Self.mappingName),
            subject: try columns.subject(entity: Self.mappingName),
            statement: try columns.statement(entity: Self.mappingName),
            origin: try Mapping.value(FactOrigin.self, origin, entity: Self.mappingName, field: "origin"),
            confidence: confidence,
            status: try Mapping.value(FactStatus.self, status, entity: Self.mappingName, field: "status"),
            suppressed: suppressed,
            forgottenAt: forgottenAt,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

// MARK: LearningEvent

extension LearningEventRecord {
    static let mappingName = "LearningEvent"

    func apply(_ event: LearningEvent) throws {
        let eventId = try Mapping.raw(event.id, entity: Self.mappingName)
        var columns = LearningEventColumns()
        let e = Self.mappingName
        switch event.kind {
        case .swapped(let from, let to, let slot):
            columns.kind = "swapped"
            columns.fromRecipeId = try Mapping.raw(from, entity: e)
            columns.toRecipeId = try Mapping.raw(to, entity: e)
            columns.slot = slot.rawValue
        case .rerolled(let recipe, let slot, let reason):
            columns.kind = "rerolled"
            columns.recipeId = try Mapping.raw(recipe, entity: e)
            columns.slot = slot.rawValue
            columns.rerollReason = reason?.rawValue
        case .skipped(let recipe, let slot):
            columns.kind = "skipped"
            columns.recipeId = try Mapping.raw(recipe, entity: e)
            columns.slot = slot.rawValue
        case .cooked(let recipe):
            columns.kind = "cooked"
            columns.recipeId = try Mapping.raw(recipe, entity: e)
        case .importedItem(let ingredient):
            columns.kind = "importedItem"
            columns.ingredientId = try Mapping.raw(ingredient, entity: e)
        case .reflectBackAnswered(let key, let answer):
            columns.kind = "reflectBackAnswered"
            columns.fact = try FactKeyColumns(subject: key.subject, statement: key.statement, entity: e)
            columns.answer = answer.rawValue
        }

        id = eventId
        at = event.at
        kind = columns.kind
        recipeId = columns.recipeId
        fromRecipeId = columns.fromRecipeId
        toRecipeId = columns.toRecipeId
        slot = columns.slot
        rerollReason = columns.rerollReason
        ingredientId = columns.ingredientId
        factSubjectKind = columns.fact?.subjectKind
        factSubjectMemberId = columns.fact?.subjectMemberId
        factStatementKind = columns.fact?.statementKind
        factStatementRef = columns.fact?.statementRef
        answer = columns.answer
    }

    func domain() throws -> LearningEvent {
        let e = Self.mappingName
        func slotValue() throws -> MealSlot {
            try Mapping.value(MealSlot.self, slot ?? "", entity: e, field: "slot")
        }
        func requiredID<Tag>(_ raw: String?) throws -> EntityID<Tag> {
            try Mapping.entityID(raw ?? "", entity: e)
        }
        let eventKind: LearningEventKind
        switch kind {
        case "swapped":
            eventKind = .swapped(from: try requiredID(fromRecipeId), to: try requiredID(toRecipeId), slot: try slotValue())
        case "rerolled":
            eventKind = .rerolled(
                recipe: try requiredID(recipeId), slot: try slotValue(),
                reason: try Mapping.optionalValue(RerollReason.self, rerollReason, entity: e, field: "rerollReason"))
        case "skipped":
            eventKind = .skipped(recipe: try requiredID(recipeId), slot: try slotValue())
        case "cooked":
            eventKind = .cooked(recipe: try requiredID(recipeId))
        case "importedItem":
            eventKind = .importedItem(ingredient: try requiredID(ingredientId))
        case "reflectBackAnswered":
            let columns = FactKeyColumns(
                subjectKind: factSubjectKind ?? "", subjectMemberId: factSubjectMemberId,
                statementKind: factStatementKind ?? "", statementRef: factStatementRef)
            eventKind = .reflectBackAnswered(
                key: FactKey(subject: try columns.subject(entity: e), statement: try columns.statement(entity: e)),
                answer: try Mapping.value(ReflectBackAnswer.self, answer ?? "", entity: e, field: "answer"))
        default:
            throw PersistenceError.invalidValue(entity: e, field: "kind", value: kind)
        }
        return LearningEvent(id: try Mapping.entityID(id, entity: e), kind: eventKind, at: at)
    }
}

/// The flattened payload columns of a learning event, built before the record is touched.
private struct LearningEventColumns {
    var kind = ""
    var recipeId: String?
    var fromRecipeId: String?
    var toRecipeId: String?
    var slot: String?
    var rerollReason: String?
    var ingredientId: String?
    var fact: FactKeyColumns?
    var answer: String?
}

// MARK: PromptState

extension PromptStateRecord {
    static let mappingName = "PromptState"

    func apply(_ state: PromptState) throws {
        promptId = try Mapping.raw(state.promptId, entity: Self.mappingName)
        lastShownAt = state.lastShownAt
        dismissedAt = state.dismissedAt
        answeredAt = state.answeredAt
    }

    func domain() throws -> PromptState {
        PromptState(
            promptId: try Mapping.entityID(promptId, entity: Self.mappingName),
            lastShownAt: lastShownAt,
            dismissedAt: dismissedAt,
            answeredAt: answeredAt
        )
    }
}
