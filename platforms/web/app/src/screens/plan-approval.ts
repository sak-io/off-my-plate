// S-13: the approval sheet (AC-5.4, AC-5.6, AC-8.4). It shows what is being approved and offers
// "Approve" (from plan-approve-button.ts), "Not yet" and, for a revision, "Discard changes".
// Opening this sheet approves nothing; nothing here calls the approve operation directly.
import type { Reply } from "../core.js";
import { COPY, SLOT_NAME, dayHeader, recipeTitle, type DiffChange, type DiffView, type Gate, type PlanView } from "./plan-data.js";
import { createApproveButton } from "./plan-approve-button.js";
import { button, h, openSheet, type Sheet } from "./plan-dom.js";

export interface Preview { plan: PlanView; diff?: DiffView; canApprove: boolean; gate?: Gate }

export interface ApprovalHost {
  panel: HTMLElement;
  op: (name: string, args: Record<string, any>) => Promise<Reply>;
  opener: HTMLElement | null;
  blockedText: () => string | undefined;
  /** Reload the screen after the sheet closed; `toast` is announced once. */
  done: (toast?: string) => void;
}

/** "Was" / "Now" lines, words never colour alone; lock changes are not listed. */
export function diffLines(change: DiffChange): string[] {
  const lines: string[] = [];
  for (const kind of change.kinds) {
    if (kind === "swapped") {
      if (change.was) lines.push(`Was: ${recipeTitle(change.was.recipeId)}`);
      if (change.now) lines.push(`Now: ${recipeTitle(change.now.recipeId)}`);
    } else if (kind === "emptied") {
      if (change.was) lines.push(`Was: ${recipeTitle(change.was.recipeId)}`);
      lines.push("Now empty: no safe recipe");
    } else if (kind === "added") {
      lines.push("Added to the week");
      if (change.now) lines.push(`Now: ${recipeTitle(change.now.recipeId)}`);
    } else if (kind === "removed") {
      if (change.was) lines.push(`Was: ${recipeTitle(change.was.recipeId)}`);
      lines.push("Removed from the week");
    } else if (kind === "servingsChanged") {
      lines.push("Portions changed");
    }
  }
  return lines;
}

export async function openApprovalSheet(host: ApprovalHost, view: PlanView): Promise<Sheet | undefined> {
  const pre = await host.op("plan.approvalPreview", { planId: view.plan.id });
  if (!pre.ok) { host.done(COPY.saveFailed); return undefined; }
  const preview = pre.result as Preview;
  const isRevision = view.plan.basedOn !== undefined;
  const listed = (preview.diff?.changes ?? []).filter((c) => c.listed && diffLines(c).length > 0);
  const title = !isRevision ? "Approve week?" : listed.length > 0 ? `Approve ${listed.length} ${listed.length === 1 ? "change" : "changes"}?` : "Approve changes?";
  const mealCount = view.plan.meals.filter((m) => m.recipeId !== undefined).length;

  const body: Node[] = [];
  const status = h("p", { id: "approval-status", role: "status" });
  const notYet = button("Not yet", { id: "approve-not-yet" });
  body.push(h("p", { textContent: isRevision ? COPY.everythingElse : `This approves all ${mealCount} meals for this week.` }));
  for (const change of listed) {
    body.push(h("section", { class: "diff" },
      h("h3", { textContent: `${dayHeader(change.date)} ${SLOT_NAME[change.slot] ?? change.slot}` }),
      h("ul", {}, ...diffLines(change).map((l) => h("li", { textContent: l })))));
  }
  const reason = preview.canApprove ? undefined : host.blockedText() ?? "This plan can't be approved right now.";
  if (reason) status.textContent = `▲ ${reason}`; else status.textContent = `✓ ${COPY.safetyPassed}`;
  body.push(status);

  let sheet: Sheet | undefined;
  const close = (): void => { sheet?.close(); };
  const failed = h("div", { id: "approval-failed", hidden: true },
    h("p", { role: "alert", textContent: `▲ ${COPY.validatorFailed}` }));
  const ok = button("OK", { id: "approval-failed-ok" });
  ok.onclick = async () => {
    close();
    const r = await host.op("plan.regenerate", { planId: view.plan.id, keepingLocked: true });
    host.done(r.ok ? undefined : COPY.saveFailed);
  };
  failed.append(ok);
  body.push(failed);

  const approve = createApproveButton({
    planId: view.plan.id, shownContentHash: preview.plan.contentHash,
    label: isRevision ? "Approve changes" : COPY.approveWeek, enabled: preview.canApprove, op: host.op,
    onResult: (reply) => {
      if (reply.ok) { close(); host.done(isRevision ? COPY.changesApproved : COPY.weekApproved); return; }
      const code = reply.error.code;
      if (code === "validation_failed") {
        status.hidden = true; failed.hidden = false; approve.disabled = true; ok.focus();
      } else if (code === "stale_preview") {
        close(); host.done("The plan changed while this was open. Review it again.");
      } else if (code === "gate_refused") {
        status.textContent = `▲ ${host.blockedText() ?? reply.error.message}`; approve.disabled = true;
      } else {
        status.textContent = `▲ ${COPY.saveFailed}`;
      }
    },
  });
  const actions: Node[] = [notYet, approve];
  if (isRevision) {
    const discard = button("Discard changes", { id: "approve-discard", class: "danger" });
    discard.onclick = () => confirmDiscard(host, view, discard, close);
    actions.push(discard);
  }
  body.push(h("div", { class: "actions" }, ...actions));
  sheet = openSheet(host.panel, title, body, { returnFocus: host.opener });
  notYet.onclick = close;
  return sheet;
}

function confirmDiscard(host: ApprovalHost, view: PlanView, opener: HTMLElement, closeApproval: () => void): void {
  const keep = button("Keep editing", { id: "discard-keep" });
  const yes = button("Discard", { id: "discard-yes", class: "danger" });
  const inner = openSheet(host.panel, COPY.discardTitle, [h("p", { textContent: COPY.discardBody }), h("div", { class: "actions" }, yes, keep)], { role: "alertdialog", returnFocus: opener });
  keep.onclick = () => inner.close();
  yes.onclick = async () => {
    const r = await host.op("plan.discard", { planId: view.plan.id });
    inner.close(); closeApproval();
    host.done(r.ok ? undefined : COPY.saveFailed);
  };
}
