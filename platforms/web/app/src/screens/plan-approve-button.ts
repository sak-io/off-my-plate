// THE approval call site (AC-5.2, AC-5.6, ADR 0008, ADR 0016).
//
// This is the only file in the web app that may send the facade's approve operation. It is called from the
// click handler of the confirm button in the approval sheet and from nowhere else: no keyboard shortcut,
// no timer, no voice or typed text, no startup path. scripts/lint-web-approval.sh fails the build if the
// operation name or the gesture string appears in any other file, or twice in this one; CODEOWNERS requires
// the owner's review for any change here.
//
// What this does not do: the web app never builds a `UserConfirmation` (the Swift facade does that, in
// ApprovalBridge.swift, only for this operation). A hostile script on the page could still send the message;
// the browser app is the user's own code on the user's own device (see the bridge header).
import type { Reply } from "../core.js";
import { button } from "./plan-dom.js";

export interface ApproveRequest {
  /** The plan the sheet showed. */
  planId: string;
  /** The content hash the sheet showed; the facade refuses when the plan has changed since. */
  shownContentHash: string;
  label: string;
  /** False while the plan is blocked by safety or is not a draft: the button is then really disabled. */
  enabled: boolean;
  op: (name: string, args: Record<string, any>) => Promise<Reply>;
  onResult: (reply: Reply) => void;
}

/** Builds the sheet's confirm button. Its click handler is the only path to approval. */
export function createApproveButton(req: ApproveRequest): HTMLButtonElement {
  const b = button(req.label, { id: "approve-confirm", class: "primary" });
  b.disabled = !req.enabled;
  let busy = false;
  b.onclick = async (event: MouseEvent) => {
    // A click made by a script (element.click(), dispatchEvent) is not a person pressing the button.
    if (!event.isTrusted || b.disabled || busy) return;
    busy = true;
    b.disabled = true;
    b.setAttribute("aria-busy", "true");
    let reply: Reply;
    try {
      reply = await req.op("plan.approve", { planId: req.planId, shownContentHash: req.shownContentHash, gesture: "confirm-button" });
    } catch {
      reply = { ok: false, error: { code: "internal_error", message: "The request could not be completed." } };
    }
    busy = false;
    b.removeAttribute("aria-busy");
    b.disabled = !req.enabled;
    req.onResult(reply);   // may disable the button again (blocked, validator failed)
  };
  return b;
}
