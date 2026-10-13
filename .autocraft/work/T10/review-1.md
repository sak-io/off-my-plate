# T10 review, round 1: APPROVED (pending CI)

Safety: eaters match validator; hard filter matches validator semantics (tags ∪ mayContain incl. optional; unverified + hard rule excluded; unknown ingredient always excluded); generateWeek refuses invalid clearance and plans only from the snapshot; output always draft; deterministic; planner/validator agreement tests.
Decisions approved: clamp start to today (note on R8); variety ≥3 days with relaxation reason; unknown ingredient always excluded; empty slots planned; needsSchoolLunch drives lunchbox.
Tracked: WeekPlanner.swift:225 unreachable `?? 0` → precondition; generateWeek accepts request.weekStart unchecked — callers must use startDate (T12/T18).
