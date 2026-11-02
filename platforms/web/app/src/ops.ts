// Explicit classification of every facade op (W11, replaces the old READ_ONLY suffix regex).
// An op in PERSISTED triggers a snapshot save after it succeeds. An op in NOT_PERSISTED never changes saved state.
// Anything not listed here is refused by App.op, so a new facade op cannot silently skip persistence: the test
// ops.spec.ts compares these two lists with the ops the facade source actually handles.
// When unsure whether an op writes, put it in PERSISTED (an extra save is harmless; a missed save loses data).
export const PERSISTED: ReadonlySet<string> = new Set([
  "cook.mark", "cook.propose", "data.deleteAll", "data.prune",
  "household.addMember", "household.create", "household.removeMember", "household.setAgeBand", "household.setName",
  "import.confirm",
  "learning.answer", "learning.confirm", "learning.forget", "learning.refresh",
  "pantry.add", "pantry.delete", "pantry.reconfirm", "pantry.resolve", "pantry.update",
  "plan.approve", "plan.discard", "plan.generate", "plan.lock", "plan.regenerate", "plan.reroll", "plan.swap",
  "safety.addRule", "safety.confirm", "safety.confirmMember", "safety.confirmNobody", "safety.reconfirm", "safety.removeRule",
  "shopping.add", "shopping.boughtEverything", "shopping.check", "shopping.refresh", "shopping.remove",
]);

export const NOT_PERSISTED: ReadonlySet<string> = new Set([
  "gate.status", "household.get", "import.parseFile", "import.parseText",
  "learning.list", "learning.reflectBack", "meta.version",
  "pantry.list", "pantry.search",
  "plan.alternatives", "plan.approvalPreview", "plan.approved", "plan.current", "plan.get", "plan.pendingDiff", "plan.working",
  "safety.catalog", "safety.parse", "safety.recheck",
  "shopping.list", "shopping.shareText",
  "state.export",
  "state.import",   // restores from storage: the stored copy is already what was imported
]);

export type OpKind = "persisted" | "not-persisted" | "unknown";
export function classify(op: string): OpKind {
  return PERSISTED.has(op) ? "persisted" : NOT_PERSISTED.has(op) ? "not-persisted" : "unknown";
}
