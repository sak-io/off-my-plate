import Foundation
import OMPCapture
import OMPDomain
import OMPServices
import Testing

@testable import OMPFeatures

private let riceAndEggs = SpokenCommandParseResult(
    commands: [
        .add([
            spoken("rice", "Rice", qty: 2, unit: .kilogram),
            spoken("egg", "Egg", qty: 12, unit: nil),
        ])
    ],
    unparsed: [], wasTruncated: false)

@MainActor
private func makeModel(
    _ backend: FakePantryBackend, speech: FakeSpeechCapture?, parse: SpokenCommandParseResult = riceAndEggs
) -> PantryVoiceModel {
    backend.parseResult = parse
    return PantryVoiceModel(backend: backend, speech: speech)
}

/// Waits (briefly) for the listening task to hand over to the confirm card.
@MainActor
private func settle(_ model: PantryVoiceModel) async {
    for _ in 0..<300 {
        if model.state != .listening && model.state != .idle { return }
        try? await Task.sleep(for: .milliseconds(10))
    }
}

@MainActor
private func speech(
    _ availability: SpeechAvailability = .available, after: SpeechAvailability = .available
) -> FakeSpeechCapture {
    FakeSpeechCapture(
        availability: availability, availabilityAfterPrompt: after,
        scriptedTranscripts: [
            SpeechTranscript(text: "I bought 2 kg rice", isFinal: false),
            SpeechTranscript(text: "I bought 2 kg rice and a dozen eggs", isFinal: true),
        ])
}

@Suite("PantryVoiceModel (S-22, S-23)")
@MainActor
struct PantryVoiceModelTests {
    @Test("AC-9.4: what was heard is shown on the card and NOTHING is saved before the user confirms")
    func confirmToSave() async {
        let backend = FakePantryBackend()
        let model = makeModel(backend, speech: speech())
        await model.start()
        await settle(model)
        #expect(model.state == .confirm)
        #expect(model.transcript == "I bought 2 kg rice and a dozen eggs")
        #expect(backend.parsedTranscripts == ["I bought 2 kg rice and a dozen eggs"])
        #expect(model.drafts.map(\.name) == ["Rice", "Egg"])
        #expect(model.drafts.map(\.amountText) == ["2", "12"])
        #expect(model.drafts.map(\.unit) == [.kilogram, .piece])
        #expect(backend.confirmed.isEmpty)
        #expect(backend.stored.isEmpty)
        #expect(model.confirmTitle == PantryCopy.addItems(2))
        await model.confirm()
        #expect(backend.confirmed.count == 1)
        #expect(backend.stored.count == 2)
        #expect(model.savedCount == 2)
    }

    @Test("Cancel and Done-less exits save nothing")
    func cancelSavesNothing() async {
        let backend = FakePantryBackend()
        let model = makeModel(backend, speech: speech())
        await model.start()
        await settle(model)
        model.cancel()
        #expect(backend.confirmed.isEmpty)
        #expect(backend.stored.isEmpty)
        #expect(model.savedCount == nil)
    }

    @Test("Editing an amount on the card changes what is saved")
    func editBeforeConfirm() async {
        let backend = FakePantryBackend()
        let model = makeModel(backend, speech: speech())
        await model.start()
        await settle(model)
        model.toggleEditing(0)
        #expect(model.drafts[0].isEditing)
        model.setAmount(0, "3,5")
        model.setUnit(0, .gram)
        await model.confirm()
        guard case .add(let items)? = backend.confirmed.first?.first else {
            Issue.record("No add command was confirmed")
            return
        }
        #expect(items[0].qty == 3.5)
        #expect(items[0].unit == .gram)
        #expect(items[0].match.ingredientId == "rice")
        #expect(backend.stored.first?.quantity == 3.5)
    }

    @Test("An invalid amount blocks the confirm button")
    func invalidAmount() async {
        let backend = FakePantryBackend()
        let model = makeModel(backend, speech: speech())
        await model.start()
        await settle(model)
        #expect(model.canConfirm)
        model.setAmount(1, "lots")
        #expect(!model.canConfirm)
        await model.confirm()
        #expect(backend.confirmed.isEmpty)
        model.setAmount(1, "0")
        #expect(!model.canConfirm)
    }

    @Test("Skipping items drops them; skipping all returns to 'nothing understood'")
    func skip() async {
        let backend = FakePantryBackend()
        let model = makeModel(backend, speech: speech())
        await model.start()
        await settle(model)
        model.skip(0)
        #expect(model.drafts.map(\.name) == ["Egg"])
        #expect(model.confirmTitle == PantryCopy.addOneItem)
        model.skip(1)
        #expect(model.state == .nothingUnderstood)
    }

    @Test("Out-of and remove commands are listed as such and use 'Update pantry'")
    func markOutAndRemove() async {
        let backend = FakePantryBackend()
        let parse = SpokenCommandParseResult(
            commands: [
                .markOut([spoken("milk", "Milk", qty: nil, unit: nil)]),
                .remove([spoken("onion", "Onion", qty: nil, unit: nil)]),
            ], unparsed: [], wasTruncated: false)
        let model = makeModel(backend, speech: speech(), parse: parse)
        await model.start()
        await settle(model)
        #expect(model.drafts.map(\.kind) == [.markOut, .remove])
        #expect(model.confirmTitle == PantryCopy.updatePantry)
        #expect(model.canConfirm)
        await model.confirm()
        #expect(backend.confirmed.first?.count == 2)
    }

    @Test("AC-9.4: a partly understood sentence keeps the rest for 'Add it by hand' (G9)")
    func partial() async {
        let backend = FakePantryBackend()
        let parse = SpokenCommandParseResult(
            commands: [.add([spoken("rice", "Rice", qty: 2, unit: .kilogram)])],
            unparsed: ["some of that stuff"], wasTruncated: false)
        let model = makeModel(backend, speech: speech(), parse: parse)
        await model.start()
        await settle(model)
        #expect(model.state == .confirm)
        #expect(model.unparsedText == "some of that stuff")
        #expect(model.byHandPrefill.name == "some of that stuff")
        #expect(model.byHandPrefill.transcript == "I bought 2 kg rice and a dozen eggs")
    }

    @Test("C-131: nothing understood shows the transcript; Try again listens again")
    func nothingUnderstood() async {
        let backend = FakePantryBackend()
        let fake = speech()
        let model = makeModel(
            backend, speech: fake, parse: SpokenCommandParseResult(commands: [], unparsed: ["blah"], wasTruncated: false))
        await model.start()
        await settle(model)
        #expect(model.state == .nothingUnderstood)
        #expect(model.transcript == "I bought 2 kg rice and a dozen eggs")
        #expect(!model.canConfirm)
        await model.start()
        await settle(model)
        #expect(fake.startCount == 2)
        #expect(backend.confirmed.isEmpty)
    }

    @Test("AC-9.5: 'approve it' heard on the pantry sheet does nothing (it has no approval path)")
    func approveDoesNothing() async {
        let backend = FakePantryBackend()
        let parse = SpokenCommandParseResult(commands: [.openApprovalSheet], unparsed: [], wasTruncated: false)
        let model = makeModel(backend, speech: speech(), parse: parse)
        await model.start()
        await settle(model)
        #expect(model.state == .nothingUnderstood)
        #expect(model.drafts.isEmpty)
        #expect(backend.confirmed.isEmpty)
    }

    @Test("A stream that ends early (call, backgrounding) keeps the transcript and shows C-132")
    func interrupted() async {
        let backend = FakePantryBackend()
        let model = makeModel(backend, speech: speech())
        await model.start()
        await settle(model)
        model.finishListening(interrupted: true)
        #expect(model.wasInterrupted)
        #expect(model.state == .confirm)
    }

    @Test("AC-9.5: permission denied shows S-23 (C-134) and never starts the microphone")
    func denied() async {
        let fake = speech(.permissionDenied)
        let model = makeModel(FakePantryBackend(), speech: fake)
        await model.start()
        #expect(model.state == .unavailable(.permissionDenied))
        #expect(fake.startCount == 0)
        #expect(fake.requestAuthorizationCount == 0)
    }

    @Test("AC-9.5: unsupported, restricted or unavailable voice shows S-23 (C-135)")
    func unavailable() async {
        for reason in [SpeechAvailability.onDeviceUnsupported, .restricted, .recognizerUnavailable] {
            let fake = speech(reason)
            let model = makeModel(FakePantryBackend(), speech: fake)
            await model.start()
            #expect(model.state == .unavailable(reason))
            #expect(fake.startCount == 0)
        }
    }

    @Test("No speech adapter at all is the same as unavailable")
    func noAdapter() async {
        let model = makeModel(FakePantryBackend(), speech: nil)
        await model.start()
        #expect(model.state == .unavailable(.recognizerUnavailable))
    }

    @Test("Permission is asked just in time; granting starts listening, declining shows S-23")
    func justInTime() async {
        let granted = speech(.needsPermission, after: .available)
        let model = makeModel(FakePantryBackend(), speech: granted)
        await model.start()
        await settle(model)
        #expect(granted.requestAuthorizationCount == 1)
        #expect(granted.startCount == 1)
        #expect(model.state == .confirm)

        let declined = speech(.needsPermission, after: .permissionDenied)
        let other = makeModel(FakePantryBackend(), speech: declined)
        await other.start()
        #expect(declined.requestAuthorizationCount == 1)
        #expect(declined.startCount == 0)
        #expect(other.state == .unavailable(.permissionDenied))
    }

    @Test("A failed save keeps the card with C-095 and saves nothing")
    func failedConfirm() async {
        let backend = FakePantryBackend()
        let model = makeModel(backend, speech: speech())
        await model.start()
        await settle(model)
        backend.failure = PantryFixtureError.boom
        await model.confirm()
        #expect(model.errorMessage == PantryCopy.saveFailed)
        #expect(model.savedCount == nil)
        #expect(model.state == .confirm)
        #expect(backend.stored.isEmpty)
    }
}
