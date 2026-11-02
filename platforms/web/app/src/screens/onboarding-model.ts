// Pure logic for the onboarding and safety screens (no DOM, no core calls): chip labels, the list of
// "things to avoid" the person is building, the per-person summary shown on S-02b, and the wire form of
// the items. Copy ids refer to docs/design/copy.md.

export interface MemberJson {
  id: string;
  label: { number: number; role: "adult" | "child" };
  name?: string;
  safetyStatus: "unasked" | "stated" | "confirmedNone";
  deletedAt?: string;
}
export interface RuleJson { id: string; restriction?: string; scope: "household" | { member: { _0: string } } | Record<string, unknown>; excludedTags?: string[] }
export interface HouseholdJson { id: string; members: MemberJson[]; rules: RuleJson[] }

/** C-023b. Order is the catalog's display order; ids are the core's restriction ids. */
export const CHIP_LABELS: Record<string, string> = {
  "peanuts": "Peanuts", "tree-nuts": "Tree nuts", "milk": "Dairy/milk", "egg": "Egg", "wheat-gluten": "Wheat/gluten",
  "soy": "Soy", "sesame": "Sesame", "mustard": "Mustard", "fish": "Fish", "shellfish": "Shellfish", "beef": "Beef",
  "pork": "Pork", "vegetarian": "Vegetarian", "jain": "Jain (no onion, garlic, root veg)",
};
export function chipLabel(id: string): string { return CHIP_LABELS[id] ?? id; }

/** C-035b. Cuisine chips (open item U5: must match the seed recipes' cuisine tags). */
export const CUISINES = ["North Indian", "South Indian", "Gujarati / Maharashtrian", "Bengali / East Indian", "A bit of everything"];

export const MAX_PEOPLE = 12;

export function activeMembers(h: HouseholdJson | undefined): MemberJson[] {
  return (h?.members ?? []).filter((m) => m.deletedAt === undefined || m.deletedAt === null);
}
export function memberName(m: MemberJson): string {
  return m.name && m.name.trim() !== "" ? m.name : `${m.label.role === "adult" ? "Adult" : "Child"} ${m.label.number}`;
}

/** One thing to avoid. `restriction` set = a known item; otherwise `text` is an unmapped phrase that must be
 *  resolved (pick a restriction) or removed before anything can be saved (AC-2.4). */
export interface Item { key: number; restriction?: string; text?: string; scope: string }
export const EVERYONE = "household";

export function unresolved(items: Item[]): Item[] { return items.filter((i) => i.restriction === undefined); }
export function hasRestriction(items: Item[], restriction: string, scope: string): boolean {
  return items.some((i) => i.restriction === restriction && i.scope === scope);
}

/** Resolves a typed name hint ("Meera") to a member scope, else Everyone (the safer default, G3). */
export function scopeForHint(hint: string | undefined, members: MemberJson[]): string {
  if (members.length <= 1 || !hint) return EVERYONE;
  const h = hint.trim().toLowerCase();
  const m = members.find((x) => memberName(x).toLowerCase() === h);
  return m ? m.id : EVERYONE;
}

/** The wire form for safety.confirm / safety.confirmMember. Refuses (throws) if anything is unresolved: the
 *  UI disables Continue first, this is the second lock. Unmapped text is never sent as if it were safe. */
export function toApiItems(items: Item[], knownMembers: string[]): Array<{ restriction: string; scope: { kind: "household" } | { kind: "member"; memberId: string } }> {
  if (unresolved(items).length > 0) throw new Error("unresolved items");
  return items.map((i) => {
    if (i.scope === EVERYONE) return { restriction: i.restriction!, scope: { kind: "household" as const } };
    if (!knownMembers.includes(i.scope)) throw new Error("unknown member");
    return { restriction: i.restriction!, scope: { kind: "member" as const, memberId: i.scope } };
  });
}

export interface SummaryRow { who: string; what: string }
/** S-02b rows (C-027a): Everyone, then each person with their own items, then "Everyone else: nothing to avoid"
 *  when some people are not covered by anything. */
export function summarise(items: Item[], members: MemberJson[]): SummaryRow[] {
  const rows: SummaryRow[] = [];
  const names = (list: Item[]) => list.map((i) => chipLabel(i.restriction ?? i.text ?? "")).join(", ");
  const every = items.filter((i) => i.scope === EVERYONE);
  if (every.length > 0) rows.push({ who: "Everyone", what: names(every) });
  const withOwn = new Set<string>();
  for (const m of members) {
    const own = items.filter((i) => i.scope === m.id);
    if (own.length > 0) { rows.push({ who: memberName(m), what: names(own) }); withOwn.add(m.id); }
  }
  if (every.length === 0) {
    const uncovered = members.filter((m) => !withOwn.has(m.id));
    if (uncovered.length > 0) rows.push({ who: withOwn.size > 0 ? "Everyone else" : "Everyone", what: "Nothing to avoid" });
  }
  return rows;
}

/** The plain-language sentence for the 180-day card (C-040a / C-040b). */
export function ruleSummary(h: HouseholdJson, members: MemberJson[]): string {
  if (h.rules.length === 0) return "Nobody has anything to avoid";
  const byWho = new Map<string, string[]>();
  for (const r of h.rules) {
    const scope = r.scope as Record<string, any>;
    const memberId = scope && typeof scope === "object" && scope.member ? String(scope.member._0) : undefined;
    const m = memberId ? members.find((x) => x.id === memberId) : undefined;
    const who = memberId ? (m ? memberName(m) : undefined) : "Everyone";
    if (who === undefined) continue;                 // a rule for a removed person covers nobody
    const list = byWho.get(who) ?? [];
    list.push(chipLabel(r.restriction ?? "something"));
    byWho.set(who, list);
  }
  if (byWho.size === 0) return "Nobody has anything to avoid";
  return [...byWho.entries()].map(([who, what]) => `${who}: ${what.join(", ")}`).join("; ");
}
