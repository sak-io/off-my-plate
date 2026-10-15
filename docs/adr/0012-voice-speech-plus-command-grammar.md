# ADR 0012: Voice = Apple Speech + a deterministic command grammar

- **Status:** Accepted (owner: tech §8.3, §7.2 `parseSpokenCommand` fallback; spec G9)
- **Date:** 2026-10-12

## Context
v1 has no model. Voice covers the pantry only, plus "approve it" opening the sheet.

## Decision
- `OMPCapture.SpeechCapture` wraps `SFSpeechRecognizer` with **`requiresOnDeviceRecognition = true` always**. If `supportsOnDeviceRecognition` is false for en-IN/en-US, voice is `.onDeviceUnsupported` (UX C-135) and the user types instead. Server recognition would be a network request, which AC-13.2 forbids. Purpose string C-137 reads "Speech stays on this device." Permissions are requested just in time, and each unavailability reason is a typed `SpeechAvailability` state (AC-9.5). The same capture also feeds the safety screen's voice input (S-02), parsed by `SafetyTextParser`.
- `OMPDomain.SpokenCommandParser` is a hand-written tokenizer plus grammar: `ADD := (i )?(bought|got|picked up|add|added) ITEMLIST`, `OUT := (we're|we are )?(out of|used up|finished|ran out of) ITEMLIST`, `REMOVE := (remove|delete) ITEMLIST`, `APPROVE := approve( it| the plan)?|looks good` -> `.openApprovalSheet`. `ITEMLIST := ITEM ((,|and) ITEM)*`, `ITEM := QTY? UNIT? (of)? NAME`. Numbers can be digits, words (one to twenty, thirty to hundred), "a/an", "half", "a dozen", "one and a half" and "half a kilo". Output is `[ParsedPantryCommand]` plus an unparsed remainder. Anything unparsed opens the manual form prefilled with the transcript.
- `SpeechAnalyzer` (iOS 26) is not used. The minimum OS is 18.

## Alternatives considered
1. Regex-only parsing. Rejected: brittle for lists joined by "and".
2. App Intents/Siri vocabulary. Deferred by the spec.
3. Allow server-based recognition as a fallback. Rejected: it sends audio off-device and breaks AC-13.2 and the privacy promise.

## Consequences
- A golden-transcript fixture file grows with real phrasings from beta users (with consent, typed in by testers, never uploaded).
