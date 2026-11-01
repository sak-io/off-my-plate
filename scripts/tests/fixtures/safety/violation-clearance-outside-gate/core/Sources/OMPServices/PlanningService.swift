func plan(_ household: Household) {
    let forged = SafetyClearance(household: household, issuedAt: now)
    let other = SafetyClearance.init(household: household, issuedAt: now)
}
