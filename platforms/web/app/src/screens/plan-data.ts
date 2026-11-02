// Shapes of the facade's plan answers, the copy catalogue strings used by the plan screens
// (docs/design/copy.md C-050 to C-084), and small pure helpers. No DOM here.
import { INGREDIENT_NAMES, RECIPES } from "../recipes-data.js";

export interface Serving { memberId: string; portion: number; notEating: boolean }
export interface Meal {
  id: string; date: string; slot: string; recipeId?: string; emptyReason?: string; locked: boolean;
  servings: Serving[]; reasons: Record<string, any>[]; cooked?: unknown; blockedBySafety: boolean;
}
export interface PlanBody {
  id: string; seriesId: string; revision: number; basedOn?: string; weekStart: string; status: string;
  meals: Meal[]; approval?: { approvedAt: string };
}
export interface PlanView { plan: PlanBody; contentHash: string; effectivelyApproved: boolean; blockedMealIds: string[] }
export interface DiffChange { date: string; slot: string; kinds: string[]; listed: boolean; was?: Meal; now?: Meal }
export interface DiffView { changes: DiffChange[]; listedCount: number }
export interface Gate { status: string; reason?: string; memberIds?: string[] }
export interface Current { seriesId?: string; working?: PlanView; approved?: PlanView; pendingDiff?: DiffView; gate: Gate }
export interface Member { id: string; label: { role: string; number: number }; name?: string; deletedAt?: string }

export const COPY = {
  loading: "Planning your week…",
  planError: "I couldn't make a plan just now. Please try again.",
  tryAgain: "Try again",
  title: "This week",
  statusDraft: "Draft · not in use yet",
  statusPending: "Changes not approved yet",
  banner: "A starting point. Swap anything and I'll learn.",
  approveWeek: "Approve week",
  approveCaption: "Builds your shopping list and lets you mark meals cooked.",
  noPlan: "No plan for this week",
  makePlan: "Make a plan",
  emptySlot: "No safe recipe for this meal yet.",
  emptyWhyButton: "Why?",
  emptyWhy: "None of my recipes fit everyone's must-avoid list for this meal. You could mark someone as not eating, or plan this one yourself.",
  draftCaption: "Approve the week to mark meals cooked.",
  swapEmpty: "No other safe recipe for this meal. Try changing who's eating.",
  swapped: "Swapped. Changes need your approval.",
  weekApproved: "Week approved. Your shopping list is ready.",
  changesApproved: "Changes approved. Your list is updated.",
  validatorFailed: "Something changed since this plan was made, so I need to replace a few meals to keep everyone safe.",
  discardTitle: "Discard your changes?",
  discardBody: "Your approved plan stays as it is.",
  regenerateTitle: "Replace all unlocked meals?",
  regenerateBody: "Locked meals stay.",
  safetyChanged: "Your safety answers changed. Some meals need replacing.",
  updatePlan: "Update plan",
  safetyPassed: "Safety check passed for everyone",
  everythingElse: "Everything else stays as approved.",
  disclaimer: "Not medical advice. Check ingredients and labels, especially for allergies.",
  saveFailed: "Something went wrong saving that. Your other information is safe. Please try again.",
} as const;

export const SLOT_NAME: Record<string, string> = { breakfast: "Breakfast", lunch: "Lunch", dinner: "Dinner", snack: "Snack", lunchbox: "Lunchbox" };
export const REROLL_REASONS: [string, string][] = [["dontFeelLikeIt", "Don't feel like it"], ["tooLong", "Too long"], ["kidsWontEatIt", "Kids won't eat it"]];

const DAYS = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];
const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

/** "2026-10-12" to a UTC date (calendar arithmetic only; no time zone is involved). */
function utc(date: string): Date {
  const [y, m, d] = date.split("-").map(Number);
  return new Date(Date.UTC(y ?? 1970, (m ?? 1) - 1, d ?? 1));
}
export const dayName = (date: string): string => DAYS[utc(date).getUTCDay()] ?? date;
export const dayHeader = (date: string): string => `${dayName(date)} ${utc(date).getUTCDate()}`;
export function rangeText(weekStart: string): string {
  const a = utc(weekStart), b = new Date(a.getTime() + 6 * 86_400_000);
  return `${DAYS[a.getUTCDay()]!.slice(0, 3)} ${a.getUTCDate()} – ${DAYS[b.getUTCDay()]!.slice(0, 3)} ${b.getUTCDate()} ${MONTHS[b.getUTCMonth()]}`;
}
export function approvedOn(iso: string): string {
  const d = new Date(iso);
  return Number.isNaN(d.getTime()) ? "" : `${DAYS[d.getUTCDay()]!.slice(0, 3)} ${d.getUTCDate()} ${MONTHS[d.getUTCMonth()]}`;
}

export const recipeTitle = (id: string | undefined): string => (id === undefined ? "" : RECIPES[id]?.title ?? "A recipe");
export const recipeMinutes = (id: string | undefined): number | undefined => (id === undefined ? undefined : RECIPES[id]?.minutes);
export const ingredientName = (id: string): string => INGREDIENT_NAMES[id] ?? id;

/** C-084 template reasons (AC-4.7): the first reason that has copy. */
export function reasonText(reasons: Record<string, any>[], slot: string): string | undefined {
  for (const r of reasons) {
    const key = Object.keys(r)[0];
    if (key === undefined) continue;
    const inner = r[key] as Record<string, unknown> | undefined;
    const first = inner && typeof inner === "object" ? Object.values(inner)[0] : undefined;
    switch (key) {
      case "usesYourIngredient": case "usesExpiringIngredient": if (typeof first === "string") return `Uses your ${ingredientName(first).toLowerCase()}`; break;
      case "quickWeekday": return `Quick weekday ${(SLOT_NAME[typeof first === "string" ? first : slot] ?? slot).toLowerCase()}`;
      case "goodForLunchboxes": return "Good for lunchboxes";
      case "differentFromYesterday": return "Something different from yesterday";
      case "cookedOften": return "You cook this often";
      default: break;
    }
  }
  return undefined;
}

export function memberName(m: Member): string {
  return m.name && m.name.trim() !== "" ? m.name : `${m.label.role === "child" ? "Child" : "Adult"} ${m.label.number}`;
}

export function portionText(s: Serving): string {
  if (s.notEating) return "Not eating";
  return `${s.portion} ${s.portion === 1 ? "portion" : "portions"}`;
}

export function quantityText(q: number): string {
  return String(Math.round(q * 100) / 100);
}

export const slotKey = (m: { date: string; slot: string }): string => `${m.date}|${m.slot}`;
