/// Scriptable `SpeechCapture` for view-model and UI tests (no microphone, no Speech framework).
@MainActor
public final class FakeSpeechCapture: SpeechCapture {
    public var currentAvailability: SpeechAvailability
    /// What `requestAuthorization()` moves to when the state was `.needsPermission`.
    public var availabilityAfterPrompt: SpeechAvailability
    /// Transcripts delivered by `start()`, in order.
    public var scriptedTranscripts: [SpeechTranscript]
    public private(set) var requestAuthorizationCount = 0
    public private(set) var startCount = 0
    public private(set) var stopCount = 0

    public init(
        availability: SpeechAvailability = .available,
        availabilityAfterPrompt: SpeechAvailability = .available,
        scriptedTranscripts: [SpeechTranscript] = []
    ) {
        self.currentAvailability = availability
        self.availabilityAfterPrompt = availabilityAfterPrompt
        self.scriptedTranscripts = scriptedTranscripts
    }

    public func availability() -> SpeechAvailability { currentAvailability }

    public func requestAuthorization() async -> SpeechAvailability {
        requestAuthorizationCount += 1
        if currentAvailability == .needsPermission { currentAvailability = availabilityAfterPrompt }
        return currentAvailability
    }

    public func start() throws -> AsyncThrowingStream<SpeechTranscript, Error> {
        guard currentAvailability == .available else {
            throw SpeechCaptureError.unavailable(currentAvailability)
        }
        startCount += 1
        let transcripts = scriptedTranscripts
        return AsyncThrowingStream { continuation in
            for transcript in transcripts { continuation.yield(transcript) }
            continuation.finish()
        }
    }

    public func stop() { stopCount += 1 }
}
