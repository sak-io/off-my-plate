# T16 delta review (sanitiser fix): APPROVED (pending CI)

Orphan marks become U+FFFD (separator); marks after letters unchanged (Malayalam/Devanagari); FFFD never counts as understood; cap logic consistent; compile risk low.
Tracked MINORs: Prepend (Cf) characters followed by a space may form a non-whitespace-initial Character, not covered by sanitiser/tests; droppedWords check is partly circular (explicit describe assertions cover). NIT: "approve <mark>" still opens approval sheet (safe, intended?).
