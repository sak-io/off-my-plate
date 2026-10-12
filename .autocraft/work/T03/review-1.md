# T03 review, round 1: CHANGES REQUESTED

CI green on c177c6c (Linux + macOS). Lint green on a fresh clone. LocalDate verified exhaustively for 0001-01-01..9999-12-31 against Python's datetime (0 mismatches).

- [MAJOR] ValidationReport.swift:33/40: Codable synthesizes a public init(from:), so any module can decode a passing report — defeats ADR 0007/0008. Drop Decodable (Encodable optional), document the exception, change CodableRoundTripTests.swift:252-255.
- [MINOR] `package` init lets any Core target build a report → lint-safety rule (only Sources/OMPSafetyCheck and Tests may call `ValidationReport(`) — track for T09.
- [MINOR] Stored JSON shapes not pinned → golden JSON tests for PlannedMeal with reasons, member-scoped Rule, both PantryItemRef cases, a LearningEventKind, a FactKey; or document that T20 DTOs own the stored format and track there.
- [MINOR] EntityID.swift:20,25: empty id encodes but can't decode → throw on encode or precondition in inits; test.
- [MINOR] InMemoryRepository.swift:42-46: single-household rule not enforced → replace or assert; document in protocol.
- [MINOR] No atomic multi-entity save → track for T18/T20 before approve.
- [MINOR] Member.swift:65-67: confirmed status with nil safetyConfirmedAt → SafetyGate must fail closed; track for T08.
- [NIT] EntityID ordering doc wording; [NIT] LocalDate safelyAdding for user input later.

Deviations D1–D7 accepted. Declare "ValidationReport not Decodable" as a deviation.
