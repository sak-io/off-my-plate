/// `SpeechCapture` built on a `SpeechRecognitionBackend`. Holds the availability and
/// just-in-time permission logic; the backend does the platform work.
@MainActor
public final class OnDeviceSpeechCapture: SpeechCapture {
    private let backend: any SpeechRecognitionBackend
    private var isRunning = false

    public init(backend: any SpeechRecognitionBackend) {
        self.backend = backend
    }

    public func availability() -> SpeechAvailability {
        SpeechAvailability.resolve(backend.environment())
    }

    public func requestAuthorization() async -> SpeechAvailability {
        let initial = backend.environment()
        // Never prompt for something that cannot work, or that the system forbids.
        guard initial.supportsOnDeviceRecognition, initial.speech != .restricted else {
            return SpeechAvailability.resolve(initial)
        }
        if initial.speech == .notDetermined {
            _ = await backend.requestSpeechPermission()
        }
        // Skip the microphone prompt if speech was just refused: voice is off either way.
        let afterSpeech = backend.environment()
        if afterSpeech.microphone == .undetermined,
           afterSpeech.speech == .authorized {
            _ = await backend.requestMicrophonePermission()
        }
        return availability()
    }

    public func start() throws -> AsyncThrowingStream<SpeechTranscript, Error> {
        let state = availability()
        guard state == .available else { throw SpeechCaptureError.unavailable(state) }
        guard !isRunning else { throw SpeechCaptureError.alreadyRunning }
        let upstream = try backend.startRecognition()
        isRunning = true
        let (stream, continuation) = AsyncThrowingStream<SpeechTranscript, Error>.makeStream()
        let relay = Task { [weak self] in
            do {
                for try await transcript in upstream { continuation.yield(transcript) }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
            self?.isRunning = false
        }
        continuation.onTermination = { @Sendable _ in relay.cancel() }
        return stream
    }

    public func stop() {
        guard isRunning else { return }
        backend.stopRecognition()
    }
}
