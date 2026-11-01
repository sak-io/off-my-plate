/// Accessibility identifiers of the Pantry screens and the cooked sheet. The UI tests
/// (`App/OffMyPlateUITests/PantryUITests.swift`) repeat these strings; per-item ones end with the
/// pantry item's raw id (or the ingredient's id on the cooked sheet).
extension AccessibilityID {
    static let pantryList = "pantry.list"
    static let pantryEmpty = "pantry.empty"
    static let pantryEmptyAdd = "pantry.empty.add"
    static let pantryEmptySpeak = "pantry.empty.speak"
    static let pantryNoResults = "pantry.noResults"
    static let pantryError = "pantry.error"
    static let pantryErrorRetry = "pantry.error.retry"
    static let pantryLoading = "pantry.loading"
    static let pantrySearch = "pantry.search"
    static let pantrySearchClear = "pantry.search.clear"
    static let pantryAdd = "pantry.add"
    static let pantrySpeak = "pantry.speak"
    static func pantryGroup(_ location: String) -> String { "pantry.group.\(location)" }
    static func pantryRow(_ id: String) -> String { "pantry.row.\(id)" }
    static func pantryStale(_ id: String) -> String { "pantry.stale.\(id)" }
    static func pantryStillHaveIt(_ id: String) -> String { "pantry.stillHaveIt.\(id)" }
    static func pantryUnresolved(_ id: String) -> String { "pantry.unresolved.\(id)" }
    static func pantryMatch(_ id: String) -> String { "pantry.match.\(id)" }
    static func pantryDelete(_ id: String) -> String { "pantry.delete.\(id)" }

    static let pantryForm = "pantryForm.sheet"
    static let pantryFormCancel = "pantryForm.cancel"
    static let pantryFormSave = "pantryForm.save"
    static let pantryFormName = "pantryForm.name"
    static let pantryFormAmount = "pantryForm.amount"
    static let pantryFormUnit = "pantryForm.unit"
    static let pantryFormLocation = "pantryForm.location"
    static let pantryFormUseByToggle = "pantryForm.useBy.toggle"
    static let pantryFormUseBy = "pantryForm.useBy"
    static let pantryFormDelete = "pantryForm.delete"
    static let pantryFormTranscript = "pantryForm.transcript"
    static let pantryFormError = "pantryForm.error"
    static let pantryFormAsTyped = "pantryForm.asTyped"
    static func pantryFormSuggestion(_ id: String) -> String { "pantryForm.suggestion.\(id)" }

    static let voiceSheet = "voice.sheet"
    static let voiceCancel = "voice.cancel"
    static let voiceListening = "voice.listening"
    static let voiceTranscript = "voice.transcript"
    static let voiceDone = "voice.done"
    static let voiceConfirm = "voice.confirm"
    static let voiceConfirmCard = "voice.confirmCard"
    static let voiceConfirmAdd = "voice.confirm.add"
    static let voiceUnparsed = "voice.unparsed"
    static let voiceAddByHand = "voice.addByHand"
    static let voiceNothing = "voice.nothing"
    static let voiceTryAgain = "voice.tryAgain"
    static let voiceTypeInstead = "voice.typeInstead"
    static let voiceDenied = "voice.denied"
    static let voiceUnavailable = "voice.unavailable"
    static let voiceOpenSettings = "voice.openSettings"
    static let voiceError = "voice.error"
    static func voiceItem(_ index: Int) -> String { "voice.item.\(index)" }
    static func voiceItemEdit(_ index: Int) -> String { "voice.item.edit.\(index)" }
    static func voiceItemAmount(_ index: Int) -> String { "voice.item.amount.\(index)" }
    static func voiceItemSkip(_ index: Int) -> String { "voice.item.skip.\(index)" }

    static let cookedSheet = "cooked.sheet"
    static let cookedCancel = "cooked.cancel"
    static let cookedUpdate = "cooked.update"
    static let cookedLoading = "cooked.loading"
    static let cookedError = "cooked.error"
    static let cookedEmpty = "cooked.empty"
    static func cookedLine(_ ingredient: String) -> String { "cooked.line.\(ingredient)" }
    static func cookedEdit(_ ingredient: String) -> String { "cooked.edit.\(ingredient)" }
    static func cookedField(_ ingredient: String) -> String { "cooked.field.\(ingredient)" }
    static func cookedAmount(_ ingredient: String) -> String { "cooked.amount.\(ingredient)" }
    static func cookedLess(_ ingredient: String) -> String { "cooked.less.\(ingredient)" }
    static func cookedMore(_ ingredient: String) -> String { "cooked.more.\(ingredient)" }
    static func cookedZero(_ ingredient: String) -> String { "cooked.zero.\(ingredient)" }
    static func cookedNone(_ ingredient: String) -> String { "cooked.none.\(ingredient)" }
}
