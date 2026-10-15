# T18 review, round 1: APPROVED (static; merge after green Linux CI)

Services validate at call time; approve re-reads, re-validates and saves atomically; R1 re-checks draft and active approved plan; contentVersion re-check; clamped startDate; fresh clearance per planner call; single FIFO ServiceLock; no path to an approved unblocked unsafe meal.
Deviations D1–D6 accepted (D3: callers run recheckOpenPlans() before first UI read + test; D4 assumption: lunchbox kids = child or teen band → owner).
Tracked MINORs: household save and plan re-check are separate saves (launch repair covers; add test); setLocked computes an unused clearance (comment).
