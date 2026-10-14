import Testing
@testable import OMPCapture

@MainActor
private final class StubBackend: SpeechRecognitionBackend {
    var env: SpeechEnvironment
    var speechAnswer: SpeechPermission
    var micAnswer: MicrophonePermission
    var speechPrompts = 0
    var micPrompts = 0

    init(
        _ env: SpeechEnvironment,
        speechAnswer: SpeechPermission = .authorized,
        micAnswer: MicrophonePermission = .granted
    ) {
        self.env = env
        self.speechAnswer = speechAnswer
        self.micAnswer = micAnswer
    }

    func environment() -> SpeechEnvironment { env }
    func requestSpeechPermission() async -> SpeechPermission {
        speechPrompts += 1
        env.speech = speechAnswer
        return speechAnswer
    }
    func requestMicrophonePermission() async -> MicrophonePermission {
        micPrompts += 1
        env.microphone = micAnswer
        return micAnswer
    }
    func startRecognition() throws -> AsyncThrowingStream<SpeechTranscript, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(SpeechTranscript(text: "we're out of milk", isFinal: true))
            continuation.finish()
        }
    }
    func stopRecognition() {}
}

private func env(
    _ speech: SpeechPermission = .authorized,
    _ mic: MicrophonePermission = .granted,
    onDevice: Bool = true,
    available: Bool = true
) -> SpeechEnvironment {
    SpeechEnvironment(
        speech: speech, microphone: mic,
        supportsOnDeviceRecognition: onDevice, isRecognizerAvailable: available
    )
}

@Suite("Speech availability mapping")
struct SpeechAvailabilityMappingTests {
    @Test("everything granted and on-device supported is available")
    func available() { #expect(SpeechAvailability.resolve(env()) == .available) }

    @Test("no on-device recogniser is onDeviceUnsupported, even with permissions granted (AC-13.2)")
    func onDeviceUnsupported() {
        #expect(SpeechAvailability.resolve(env(onDevice: false)) == .onDeviceUnsupported)
        #expect(SpeechAvailability.resolve(env(.notDetermined, .undetermined, onDevice: false)) == .onDeviceUnsupported)
    }

    @Test("restricted speech wins over everything")
    func restricted() {
        #expect(SpeechAvailability.resolve(env(.restricted, .denied, onDevice: false)) == .restricted)
    }

    @Test("a denied permission, speech or microphone, is permissionDenied")
    func denied() {
        #expect(SpeechAvailability.resolve(env(.denied)) == .permissionDenied)
        #expect(SpeechAvailability.resolve(env(.authorized, .denied)) == .permissionDenied)
        #expect(SpeechAvailability.resolve(env(.notDetermined, .denied)) == .permissionDenied)
    }

    @Test("an undetermined permission needs a prompt")
    func needsPermission() {
        #expect(SpeechAvailability.resolve(env(.notDetermined, .undetermined)) == .needsPermission)
        #expect(SpeechAvailability.resolve(env(.authorized, .undetermined)) == .needsPermission)
        #expect(SpeechAvailability.resolve(env(.notDetermined, .granted)) == .needsPermission)
    }

    @Test("a temporarily unavailable recogniser is recognizerUnavailable")
    func recognizerUnavailable() {
        #expect(SpeechAvailability.resolve(env(available: false)) == .recognizerUnavailable)
    }
}

@MainActor
@Suite("OnDeviceSpeechCapture permission flow")
struct OnDeviceSpeechCaptureTests {
    @Test("availability does not prompt")
    func noPromptOnQuery() {
        let backend = StubBackend(env(.notDetermined, .undetermined))
        let capture = OnDeviceSpeechCapture(backend: backend)
        #expect(capture.availability() == .needsPermission)
        #expect(backend.speechPrompts == 0 && backend.micPrompts == 0)
    }

    @Test("just-in-time flow asks speech then microphone and ends available")
    func promptsBoth() async {
        let backend = StubBackend(env(.notDetermined, .undetermined))
        let capture = OnDeviceSpeechCapture(backend: backend)
        #expect(await capture.requestAuthorization() == .available)
        #expect(backend.speechPrompts == 1 && backend.micPrompts == 1)
    }

    @Test("only undetermined permissions are prompted")
    func promptsOnlyWhatIsMissing() async {
        let backend = StubBackend(env(.authorized, .undetermined))
        let capture = OnDeviceSpeechCapture(backend: backend)
        #expect(await capture.requestAuthorization() == .available)
        #expect(backend.speechPrompts == 0 && backend.micPrompts == 1)
    }

    @Test("refusing speech skips the microphone prompt and reports permissionDenied")
    func speechRefused() async {
        let backend = StubBackend(env(.notDetermined, .undetermined), speechAnswer: .denied)
        let capture = OnDeviceSpeechCapture(backend: backend)
        #expect(await capture.requestAuthorization() == .permissionDenied)
        #expect(backend.micPrompts == 0)
    }

    @Test("refusing the microphone reports permissionDenied")
    func micRefused() async {
        let backend = StubBackend(env(.authorized, .undetermined), micAnswer: .denied)
        let capture = OnDeviceSpeechCapture(backend: backend)
        #expect(await capture.requestAuthorization() == .permissionDenied)
    }

    @Test("never prompts when on-device recognition is unsupported")
    func noPromptWhenUnsupported() async {
        let backend = StubBackend(env(.notDetermined, .undetermined, onDevice: false))
        let capture = OnDeviceSpeechCapture(backend: backend)
        #expect(await capture.requestAuthorization() == .onDeviceUnsupported)
        #expect(backend.speechPrompts == 0 && backend.micPrompts == 0)
    }

    @Test("start throws unless available")
    func startRequiresAvailable() {
        let capture = OnDeviceSpeechCapture(backend: StubBackend(env(.denied)))
        #expect(throws: SpeechCaptureError.unavailable(.permissionDenied)) { try capture.start() }
    }

    @Test("start relays the backend transcripts")
    func startRelays() async throws {
        let capture = OnDeviceSpeechCapture(backend: StubBackend(env()))
        var received: [SpeechTranscript] = []
        for try await transcript in try capture.start() { received.append(transcript) }
        #expect(received == [SpeechTranscript(text: "we're out of milk", isFinal: true)])
    }
}

@MainActor
@Suite("FakeSpeechCapture")
struct FakeSpeechCaptureTests {
    @Test("fake delivers scripted transcripts")
    func scripted() async throws {
        let fake = FakeSpeechCapture(scriptedTranscripts: [
            SpeechTranscript(text: "I bought", isFinal: false),
            SpeechTranscript(text: "I bought 1 kg onions", isFinal: true),
        ])
        var received: [String] = []
        for try await transcript in try fake.start() { received.append(transcript.text) }
        #expect(received == ["I bought", "I bought 1 kg onions"])
        #expect(fake.startCount == 1)
    }

    @Test("fake moves from needsPermission to the scripted outcome")
    func prompt() async {
        let fake = FakeSpeechCapture(availability: .needsPermission, availabilityAfterPrompt: .permissionDenied)
        #expect(await fake.requestAuthorization() == .permissionDenied)
        #expect(fake.requestAuthorizationCount == 1)
    }

    @Test("fake refuses to start when unavailable")
    func unavailable() {
        let fake = FakeSpeechCapture(availability: .onDeviceUnsupported)
        #expect(throws: SpeechCaptureError.unavailable(.onDeviceUnsupported)) { try fake.start() }
    }
}
