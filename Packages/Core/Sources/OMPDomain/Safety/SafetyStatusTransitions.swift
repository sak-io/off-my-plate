import Foundation

/// Why a safety-status transition was refused. Nothing is changed when one is thrown.
public enum SafetyTransitionError: Error, Sendable, Hashable {
    /// No member has this id.
    case unknownMember(MemberID)
    /// The member is soft-deleted.
    case deletedMember(MemberID)
    /// The member is still covered by hard rules, so it cannot be "nothing to avoid".
    case memberHasRules(MemberID)
    /// The household has hard rules, so "No, nobody" would contradict them.
    case householdHasRules
    /// A rule with this id already exists.
    case duplicateRule(RuleID)
    /// No rule has this id.
    case unknownRule(RuleID)
    /// The answer has to contain at least one rule.
    case noRules
    /// A member-scope rule names a member that does not exist or is deleted.
    case ruleForInactiveMember(MemberID)
}

/// Safety-status transitions (plan section 4.1 state diagram; AC-2.2, AC-2.3, AC-3.2, AC-3.4,
/// G3; UX U1, U3).
///
/// Every transition that represents a user answer takes the confirmation instant and stamps
/// `safetyConfirmedAt`; the 180-day re-confirmation counts from it. Each mutation also sets
/// `updatedAt`. A throwing mutation leaves the household unchanged.
extension Household {
    /// "No, nobody" (AC-2.2): every non-deleted member becomes `confirmedNone`, confirmed at
    /// `now`.
    ///
    /// - Throws: `.householdHasRules` when any hard rule exists (the user must remove them
    ///   first; rules are never deleted silently).
    public mutating func confirmNobodyAvoidsAnything(at now: Date) throws {
        guard rules.isEmpty else { throw SafetyTransitionError.householdHasRules }
        for index in members.indices where !members[index].isDeleted {
            members[index].safetyStatus = .confirmedNone
            members[index].safetyConfirmedAt = now
        }
        updatedAt = now
    }

    /// The safety summary's "Yes, save this" (AC-2.3, G3, UX U1): saves the confirmed hard
    /// rules, then every non-deleted member covered by any rule becomes `stated` and every
    /// other non-deleted member becomes `confirmedNone` ("Everyone else: nothing to avoid"),
    /// all confirmed at `now`. "Not sure who" items arrive as `.household` scope, which covers
    /// every member.
    ///
    /// - Throws: `.noRules`, `.duplicateRule`, `.ruleForInactiveMember`.
    public mutating func confirmSafetyAnswers(rules newRules: [Rule], at now: Date) throws {
        guard !newRules.isEmpty else { throw SafetyTransitionError.noRules }
        try validateNewRules(newRules)
        rules.append(contentsOf: newRules)
        for index in members.indices where !members[index].isDeleted {
            let covered = !rules(covering: members[index].id).isEmpty
            members[index].safetyStatus = covered ? .stated : .confirmedNone
            members[index].safetyConfirmedAt = now
        }
        updatedAt = now
    }

    /// A per-member "nothing to avoid" answer (plan 4.1 `unasked -> confirmedNone`, and the
    /// confirmation after the member's last rule was removed).
    ///
    /// - Throws: `.unknownMember`, `.deletedMember`, `.memberHasRules` (including household
    ///   rules, which cover everyone).
    public mutating func confirmNothingToAvoid(for memberID: MemberID, at now: Date) throws {
        let index = try activeMemberIndex(memberID)
        guard rules(covering: memberID).isEmpty else { throw SafetyTransitionError.memberHasRules(memberID) }
        members[index].safetyStatus = .confirmedNone
        members[index].safetyConfirmedAt = now
        updatedAt = now
    }

    /// Adds one user-confirmed hard rule (plan 4.1 `confirmedNone -> stated`).
    ///
    /// A member-scope rule is an explicit answer for that member, so the member becomes
    /// `stated` whatever its status. A household-scope rule turns answered members `stated`
    /// but leaves `unasked` members `unasked`: nobody answered for them yet (fails closed).
    ///
    /// - Throws: `.duplicateRule`, `.ruleForInactiveMember`.
    public mutating func addRule(_ rule: Rule, at now: Date) throws {
        try validateNewRules([rule])
        rules.append(rule)
        for index in members.indices where !members[index].isDeleted && rule.scope.covers(members[index].id) {
            let explicitlyForMember = rule.scope == .member(members[index].id)
            guard explicitlyForMember || members[index].safetyStatus != .unasked else { continue }
            members[index].safetyStatus = .stated
            members[index].safetyConfirmedAt = now
        }
        updatedAt = now
    }

    /// Removes a hard rule after the user confirmed the removal (plan 4.1
    /// `stated -> confirmedNone`: "last rule removed + confirmed"). Members that were `stated`
    /// and are no longer covered by any rule become `confirmedNone`, confirmed at `now`;
    /// `unasked` members stay `unasked`.
    ///
    /// - Throws: `.unknownRule`.
    public mutating func removeRule(_ ruleID: RuleID, confirmedAt now: Date) throws {
        guard let ruleIndex = rules.firstIndex(where: { $0.id == ruleID }) else {
            throw SafetyTransitionError.unknownRule(ruleID)
        }
        rules.remove(at: ruleIndex)
        for index in members.indices where !members[index].isDeleted && members[index].safetyStatus == .stated {
            if rules(covering: members[index].id).isEmpty {
                members[index].safetyStatus = .confirmedNone
                members[index].safetyConfirmedAt = now
            }
        }
        updatedAt = now
    }

    /// Adds a member from Settings -> Household (AC-3.2). The new member is always `unasked`
    /// (planning stays blocked until it is answered), even if household rules exist.
    ///
    /// - Returns: the new member.
    @discardableResult
    public mutating func addMember(
        role: MemberRole, ageBand: AgeBand?, at now: Date, id: MemberID = MemberID.generate()
    ) -> Member {
        let member = Member(
            id: id, label: nextLabel(for: role), ageBand: ageBand, safetyStatus: .unasked, safetyConfirmedAt: nil)
        members.append(member)
        updatedAt = now
        return member
    }

    /// Soft-deletes a member (UX U3 "Remove {name}"). A deleted member never blocks planning.
    /// Rules scoped to the member are kept (soft delete, sync-ready) but cover nobody active.
    ///
    /// - Throws: `.unknownMember`, `.deletedMember`.
    public mutating func removeMember(_ memberID: MemberID, at now: Date) throws {
        let index = try activeMemberIndex(memberID)
        members[index].deletedAt = now
        updatedAt = now
    }

    /// Changes a member's age band (AC-3.4). Crossing between a child band (infant, toddler,
    /// child) and a grown band (teen, adult, senior), or to or from "unknown" (`nil`), resets
    /// the member to `unasked` so the safety question is asked again. Rules are kept, so the
    /// re-confirmation can show them.
    ///
    /// - Returns: whether the member was reset to `unasked`.
    /// - Throws: `.unknownMember`, `.deletedMember`.
    @discardableResult
    public mutating func setAgeBand(_ ageBand: AgeBand?, for memberID: MemberID, at now: Date) throws -> Bool {
        let index = try activeMemberIndex(memberID)
        let crossed = AgeBand.safetyGroup(of: members[index].ageBand) != AgeBand.safetyGroup(of: ageBand)
        members[index].ageBand = ageBand
        if crossed {
            members[index].safetyStatus = .unasked
            members[index].safetyConfirmedAt = nil
        }
        updatedAt = now
        return crossed
    }

    /// The one-tap "Still correct?" (G3): refreshes `safetyConfirmedAt` to `now` for the given
    /// answered members, without changing status or rules. `unasked` members are skipped:
    /// there is no answer to re-confirm, they must answer the full question.
    ///
    /// - Parameter memberIDs: the members the prompt was shown for; `nil` means every
    ///   non-deleted member.
    /// - Returns: the ids that were refreshed.
    /// - Throws: `.unknownMember`, `.deletedMember` for an explicit id.
    @discardableResult
    public mutating func reconfirmSafety(for memberIDs: [MemberID]? = nil, at now: Date) throws -> [MemberID] {
        let indices = try (memberIDs ?? activeMembers.map(\.id)).map { try activeMemberIndex($0) }
        var refreshed: [MemberID] = []
        for index in indices where members[index].safetyStatus != .unasked {
            members[index].safetyConfirmedAt = now
            refreshed.append(members[index].id)
        }
        updatedAt = now
        return refreshed
    }

    private func activeMemberIndex(_ memberID: MemberID) throws -> Int {
        guard let index = members.firstIndex(where: { $0.id == memberID }) else {
            throw SafetyTransitionError.unknownMember(memberID)
        }
        guard !members[index].isDeleted else { throw SafetyTransitionError.deletedMember(memberID) }
        return index
    }

    private func validateNewRules(_ newRules: [Rule]) throws {
        var seen = Set(rules.map(\.id))
        for rule in newRules {
            guard seen.insert(rule.id).inserted else { throw SafetyTransitionError.duplicateRule(rule.id) }
            if case .member(let memberID) = rule.scope, member(memberID)?.isDeleted ?? true {
                throw SafetyTransitionError.ruleForInactiveMember(memberID)
            }
        }
    }
}

extension AgeBand {
    /// The safety-relevant grouping for re-confirmation on age-band change (AC-3.4).
    enum SafetyGroup: Hashable {
        case child
        case grown
        case unknown
    }

    static func safetyGroup(of band: AgeBand?) -> SafetyGroup {
        switch band {
        case nil: return .unknown
        case .some(.infant), .some(.toddler), .some(.child): return .child
        case .some(.teen), .some(.adult), .some(.senior): return .grown
        }
    }
}
