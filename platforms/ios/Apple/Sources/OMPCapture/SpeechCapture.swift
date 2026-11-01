/// Why voice capture can or cannot run right now (AC-9.5, ADR 0012). Every unavailable reason is
/// a typed state so the UI can show the right copy (C-134 denied, C-135 unavailable) and offer
/// "Type instead".
public enum SpeechAvailability: Sendable, Equatable, CaseIterable {
    /// Permissions granted and an on-device recogniser is ready.
    case available
    /// A permission has not been asked yet: request it just in time, when the user taps the mic.
    case needsPermission
    /// The user declined Speech Recognition or Microphone access (C-134, "Open Settings").
    case permissionDenied
    /// Access is restricted by the system (parental controls, MDM). Nothing the user can enable here.
    case restricted
    /// No en-IN/en-US recogniser supports on-device recognition. Server recognition would be a
    /// network request, so voice stays off (AC-13.2, C-135).
    case onDeviceUnsupported
    /// The recogniser exists but is temporarily unavailable (C-135).
    case recognizerUnavailable
}

/// Speech Recognition authorization, mirroring `SFSpeechRecognizerAuthorizationStatus`.
public enum SpeechPermission: Sendable, Equatable {
    case notDetermined, denied, restricted, authorized
}

/// Microphone permission, mirroring `AVAudioApplication.recordPermission`.
public enum MicrophonePermission: Sendable, Equatable {
    case undetermined, denied, granted
}

/// A snapshot of everything availability depends on.
public struct SpeechEnvironment: Sendable, Equatable {
    public var speech: SpeechPermission
    public var microphone: MicrophonePermission
    /// True when a recogniser exists for a supported locale and it supports on-device recognition.
    public var supportsOnDeviceRecognition: Bool
    /// The recogniser's own `isAvailable`.
    public var isRecognizerAvailable: Bool

    public init(
        speech: SpeechPermission,
        microphone: MicrophonePermission,
        supportsOnDeviceRecognition: Bool,
        isRecognizerAvailable: Bool
    ) {
        self.speech = speech
        self.microphone = microphone
        self.supportsOnDeviceRecognition = supportsOnDeviceRecognition
        self.isRecognizerAvailable = isRecognizerAvailable
    }
}

extension SpeechAvailability {
    /// Pure mapping from the environment to a state. Order matters: hard blockers first, and the
    /// on-device check precedes the permission prompts so we never ask for access to a feature
    /// that cannot work offline.
    public static func resolve(_ environment: SpeechEnvironment) -> SpeechAvailability {
        if environment.speech == .restricted { return .restricted }
        if !environment.supportsOnDeviceRecognition { return .onDeviceUnsupported }
        if environment.speech == .denied || environment.microphone == .denied {
            return .permissionDenied
        }
        if environment.speech == .notDetermined || environment.microphone == .undetermined {
            return .needsPermission
        }
        return environment.isRecognizerAvailable ? .available : .recognizerUnavailable
    }
}

/// One partial or final transcript from the recogniser. The text is already passed through
/// `TranscriptSanitiser`.
public struct SpeechTranscript: Sendable, Equatable {
    public var text: String
    public var isFinal: Bool

    public init(text: String, isFinal: Bool) {
        self.text = text
        self.isFinal = isFinal
    }
}

public enum SpeechCaptureError: Error, Sendable, Equatable {
    /// `start()` was called while `availability()` was not `.available`.
    case unavailable(SpeechAvailability)
    case alreadyRunning
    /// The recogniser or audio engine failed; the message is for logs only, never for the UI.
    case recognitionFailed(String)
}

/// On-device speech capture. View models depend on this protocol; the fake drives them in tests.
/// `@MainActor` because the real implementation owns an audio engine and recogniser.
@MainActor
public protocol SpeechCapture: AnyObject {
    /// Current state without prompting.
    func availability() -> SpeechAvailability
    /// Just-in-time permission flow: prompts only for what is still undetermined, and only when
    /// on-device recognition is supported. Returns the resulting state.
    func requestAuthorization() async -> SpeechAvailability
    /// Starts listening. Throws `SpeechCaptureError.unavailable` unless `availability()` is `.available`.
    /// The stream finishes after the final transcript or after `stop()`.
    func start() throws -> AsyncThrowingStream<SpeechTranscript, Error>
    /// Stops listening; the stream then delivers the final transcript and finishes.
    func stop()
}

/// The platform seam under `SpeechCapture`: wraps `SFSpeechRecognizer`, `AVAudioApplication`
/// and the audio engine so availability mapping and the permission flow are unit-testable.
@MainActor
public protocol SpeechRecognitionBackend: AnyObject {
    func environment() -> SpeechEnvironment
    func requestSpeechPermission() async -> SpeechPermission
    func requestMicrophonePermission() async -> MicrophonePermission
    func startRecognition() throws -> AsyncThrowingStream<SpeechTranscript, Error>
    func stopRecognition()
}
