#if canImport(Speech) && canImport(AVFAudio)
import AVFAudio
import Speech
import OMPDomain

/// Hands the (non-Sendable) request to the audio thread's tap. Only `append` and `endAudio`
/// are called, both thread-safe per Apple's documentation.
private final class RequestBox: @unchecked Sendable {
    let request: SFSpeechAudioBufferRecognitionRequest
    init(_ request: SFSpeechAudioBufferRecognitionRequest) { self.request = request }
}

/// `SFSpeechRecognizer` backend. `requiresOnDeviceRecognition` is always `true`: audio never
/// leaves the device (R9, ADR 0012, AC-13.2). If no supported locale can recognise on-device,
/// availability is `.onDeviceUnsupported` and nothing is started. No network API is used.
@MainActor
public final class SystemSpeechBackend: SpeechRecognitionBackend {
    /// Preference order (ADR 0012).
    public static let preferredLocaleIdentifiers: [String] = ["en-IN", "en-US"]

    private let recognizer: SFSpeechRecognizer?
    private let engine = AVAudioEngine()
    private var task: SFSpeechRecognitionTask?
    private var box: RequestBox?

    public init() {
        recognizer = Self.preferredLocaleIdentifiers
            .compactMap { SFSpeechRecognizer(locale: Locale(identifier: $0)) }
            .first { $0.supportsOnDeviceRecognition }
    }

    public func environment() -> SpeechEnvironment {
        SpeechEnvironment(
            speech: Self.map(SFSpeechRecognizer.authorizationStatus()),
            microphone: Self.map(AVAudioApplication.shared.recordPermission),
            supportsOnDeviceRecognition: recognizer?.supportsOnDeviceRecognition ?? false,
            isRecognizerAvailable: recognizer?.isAvailable ?? false
        )
    }

    public func requestSpeechPermission() async -> SpeechPermission {
        let status: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { @Sendable status in
                continuation.resume(returning: status)
            }
        }
        return Self.map(status)
    }

    public func requestMicrophonePermission() async -> MicrophonePermission {
        let granted: Bool = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { @Sendable granted in
                continuation.resume(returning: granted)
            }
        }
        return granted ? .granted : .denied
    }

    public func startRecognition() throws -> AsyncThrowingStream<SpeechTranscript, Error> {
        guard let recognizer, recognizer.supportsOnDeviceRecognition else {
            throw SpeechCaptureError.unavailable(.onDeviceUnsupported)
        }
        stopRecognition()

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        let requestBox = RequestBox(request)

        do {
            #if os(iOS)
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            #endif
            let input = engine.inputNode
            input.removeTap(onBus: 0)
            input.installTap(
                onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0),
                block: Self.makeTap(requestBox)
            )
            engine.prepare()
            try engine.start()
        } catch {
            teardownAudio()
            throw SpeechCaptureError.recognitionFailed(String(describing: error))
        }

        let (stream, continuation) = AsyncThrowingStream<SpeechTranscript, Error>.makeStream()
        task = recognizer.recognitionTask(with: request, resultHandler: Self.makeResultHandler(continuation))
        box = requestBox
        continuation.onTermination = { @Sendable [weak self] _ in
            Task { @MainActor in self?.stopRecognition() }
        }
        return stream
    }

    public func stopRecognition() {
        teardownAudio()
        box?.request.endAudio()
        box = nil
        task = nil
    }

    private func teardownAudio() {
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    // Built in a nonisolated context so the closures do not inherit @MainActor: both run on
    // background queues and would trap under Swift 6 dynamic isolation checks otherwise.
    private nonisolated static func makeTap(_ box: RequestBox) -> AVAudioNodeTapBlock {
        { buffer, _ in box.request.append(buffer) }
    }

    private nonisolated static func makeResultHandler(
        _ continuation: AsyncThrowingStream<SpeechTranscript, Error>.Continuation
    ) -> @Sendable (SFSpeechRecognitionResult?, Error?) -> Void {
        { result, error in
            if let result {
                let text = TranscriptSanitiser.sanitise(result.bestTranscription.formattedString)
                continuation.yield(SpeechTranscript(text: text, isFinal: result.isFinal))
                if result.isFinal { continuation.finish() }
            } else if let error {
                continuation.finish(throwing: SpeechCaptureError.recognitionFailed(String(describing: error)))
            }
        }
    }

    private static func map(_ status: SFSpeechRecognizerAuthorizationStatus) -> SpeechPermission {
        switch status {
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .restricted: .restricted
        case .authorized: .authorized
        @unknown default: .denied
        }
    }

    private static func map(_ permission: AVAudioApplication.recordPermission) -> MicrophonePermission {
        switch permission {
        case .undetermined: .undetermined
        case .denied: .denied
        case .granted: .granted
        @unknown default: .denied
        }
    }
}
#endif
