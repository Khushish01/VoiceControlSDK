import Foundation
import AVFoundation

/// Main entry point for the VoiceControlSDK.
/// Host app creates a configuration, initializes this engine, sets the delegate, and calls `start()`.
public final class VoiceControlEngine: NSObject {

    // MARK: - Public Properties

    public weak var delegate: VoiceControlDelegate?

    /// Current engine state.
    public private(set) var state: VoiceControlState = .idle {
        didSet {
            if oldValue != state {
                DispatchQueue.main.async { self.delegate?.voiceControl(self, didChangeState: self.state) }
            }
        }
    }

    /// Context object the host app can update with runtime values (e.g., isWorkoutActive).
    /// Command pattern guards read from this context.
    public let context = VoiceControlContext()

    /// Current language locale identifier.
    public private(set) var currentLocale: String

    /// The configuration this engine was initialized with.
    public let configuration: VoiceControlConfiguration

    // MARK: - Internal Engines

    private let interpreter: CommandInterpreterEngine
    private let speechEngine: SpeechRecognitionEngine
    private let feedbackEngine: FeedbackEngine
    private let commandQueue: CommandQueue

    private var autoSleepTimer: Timer?
    private var suppressFeedbackResume: Bool = false

    // MARK: - Init

    public init(configuration: VoiceControlConfiguration) {
        self.configuration = configuration
        self.currentLocale = configuration.languages.first?.localeIdentifier ?? "en-US"

        self.interpreter = CommandInterpreterEngine(configuration: configuration)

        // Build contextual strings from wake words + vocabulary to help Apple's recognizer
        var hints: [String] = []
        hints.append(contentsOf: configuration.wakeWord.triggerWords.map { $0.capitalized })
        for lang in configuration.languages {
            if let prefixes = configuration.wakeWord.prefixes[lang.localeIdentifier] {
                for prefix in prefixes {
                    for trigger in configuration.wakeWord.triggerWords {
                        hints.append("\(prefix.capitalized) \(trigger.capitalized)")
                    }
                }
            }
        }

        self.speechEngine = SpeechRecognitionEngine(
            interpreter: interpreter,
            silenceTimeout: configuration.silenceTimeout,
            initialLocale: currentLocale,
            contextualStrings: hints
        )

        self.feedbackEngine = FeedbackEngine(
            speechRate: configuration.speechRate,
            speechPitch: configuration.speechPitch,
            voiceIdentifiers: configuration.voiceIdentifiers
        )

        // Use a temporary unowned reference pattern to avoid capturing self before super.init
        self.commandQueue = CommandQueue(
            feedbackEngine: feedbackEngine,
            currentLocale: { "en-US" } // placeholder, replaced after super.init
        )

        super.init()

        // Now safe to capture self
        commandQueue.updateLocaleProvider { [weak self] in self?.currentLocale ?? "en-US" }
        setupSpeechEngineDelegate()
        setupFeedbackCallbacks()
        setupQueueCallbacks()
    }

    // MARK: - Public API

    /// Request microphone and speech recognition permissions.
    public func requestPermissions(completion: @escaping (Bool) -> Void) {
        speechEngine.requestPermissions(completion: completion)
    }

    /// Start the engine — begins passive listening for wake word.
    public func start() {
        startPassiveListening()
    }

    /// Stop the engine completely.
    public func stop() {
        autoSleepTimer?.invalidate()
        autoSleepTimer = nil
        suppressFeedbackResume = true
        speechEngine.stopListening()
        feedbackEngine.stopSpeaking()
        commandQueue.clearQueue()
        state = .idle
    }

    /// Manually activate voice control (e.g., user tapped floating mic button).
    /// Skips wake word detection and goes directly to active listening.
    public func activateManually() {
        activateVoiceControl(actionId: "default")
    }

    /// Toggle between active and passive modes (for mic button).
    public func toggleActivation() {
        switch state {
        case .idle, .passiveListening:
            activateManually()
        case .activeListening:
            speechEngine.stopListening()
            startPassiveListening()
        case .processing:
            break
        }
    }

    /// Switch to a different language at runtime.
    /// Always resets to passive listening since the previous session context is lost.
    public func setLanguage(_ localeIdentifier: String) {
        guard configuration.languages.contains(where: { $0.localeIdentifier == localeIdentifier }) else {
            delegate?.voiceControl(self, didEncounterError: .unsupportedLanguage(localeIdentifier))
            return
        }
        currentLocale = localeIdentifier
        autoSleepTimer?.invalidate()
        autoSleepTimer = nil
        // Suppress the delayed onSpeakingStateChanged(false) callback that fires
        // ~800ms after stopSpeaking — it would override our passive state with active.
        suppressFeedbackResume = true
        feedbackEngine.stopSpeaking()
        commandQueue.clearQueue()
        speechEngine.stopListening()
        startPassiveListening()
    }

    // MARK: - Private: Voice Flow

    private func startPassiveListening() {
        speechEngine.setLocale(currentLocale)
        speechEngine.startListening(mode: .passive)
        state = .passiveListening
    }

    private func activateVoiceControl(actionId: String?) {
        autoSleepTimer?.invalidate()
        state = .activeListening
        speechEngine.stopListening()

        DispatchQueue.main.async {
            self.delegate?.voiceControlDidDetectWakeWord(self, actionId: actionId)
        }

        // Speak wake confirmation via queue, then listen for command
        let wakeResult = VoiceCommandResult(
            identifier: "__wake",
            rawTranscript: "",
            normalizedTranscript: "",
            isEmergency: false
        )
        commandQueue.enqueue(wakeResult)
    }

    private func handleFinishedTranscription(_ text: String) {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count >= 2 else { return }

        let command = interpreter.interpret(cleaned, locale: currentLocale, context: context)

        if let command = command {
            autoSleepTimer?.invalidate()
            commandQueue.enqueue(command)
        } else {
            // Unrecognized — prefer audio file, fall back to TTS text
            if let audioURL = delegate?.voiceControl(self, unrecognizedSpeechAudioURLFor: cleaned, language: currentLocale) {
                Task { await feedbackEngine.playAudio(url: audioURL) }
            } else if let feedbackText = delegate?.voiceControl(self, didReceiveUnrecognizedSpeech: cleaned, language: currentLocale) {
                Task { await feedbackEngine.speak(feedbackText, locale: currentLocale) }
            }
            startAutoSleepTimer()
        }
    }

    // MARK: - Private: Timers

    private func startAutoSleepTimer() {
        autoSleepTimer?.invalidate()
        autoSleepTimer = Timer.scheduledTimer(withTimeInterval: configuration.autoSleepTimeout, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.speechEngine.stopListening()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.startPassiveListening()
                }
            }
        }
    }

    // MARK: - Private: Wiring

    private func setupSpeechEngineDelegate() {
        speechEngine.delegate = self
    }

    private func setupFeedbackCallbacks() {
        feedbackEngine.onSpeakingStateChanged = { [weak self] isSpeaking in
            guard let self = self else { return }
            DispatchQueue.main.async {
                if isSpeaking {
                    // New speech starting — clear any stale suppress flag so its
                    // corresponding onSpeakingStateChanged(false) is honored.
                    self.suppressFeedbackResume = false
                    self.speechEngine.pauseListening()
                } else {
                    // If a language switch or stop() triggered stopSpeaking(), the delayed
                    // onSpeakingStateChanged(false) must not override passive/idle state.
                    if self.suppressFeedbackResume {
                        self.suppressFeedbackResume = false
                        return
                    }
                    self.state = .activeListening
                    self.speechEngine.resumeListening(mode: .active)
                    self.startAutoSleepTimer()
                }
            }
        }
    }

    private func setupQueueCallbacks() {
        commandQueue.onExecuteCommand = { [weak self] command, completion in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.delegate?.voiceControl(self, didRecognizeCommand: command, completion: completion)
            }
        }

        commandQueue.onGetFeedbackAudioURL = { [weak self] command, succeeded in
            guard let self = self else { return nil }
            return self.delegate?.voiceControl(self, feedbackAudioURLFor: command, language: self.currentLocale, succeeded: succeeded)
        }

        commandQueue.onGetFeedbackText = { [weak self] command, succeeded in
            guard let self = self else { return nil }
            return self.delegate?.voiceControl(self, feedbackTextFor: command, language: self.currentLocale, succeeded: succeeded)
        }

        commandQueue.onProcessingStateChanged = { [weak self] isProcessing in
            guard let self = self else { return }
            DispatchQueue.main.async {
                if isProcessing {
                    self.state = .processing
                }
            }
        }
    }
}

// MARK: - SpeechRecognitionEngineDelegate

extension VoiceControlEngine: SpeechRecognitionEngineDelegate {

    func speechEngineDidDetectWakeWord(actionId: String?) {
        activateVoiceControl(actionId: actionId)
    }

    func speechEngineDidTranscribePartial(_ text: String) {
        autoSleepTimer?.invalidate()
        delegate?.voiceControl(self, didTranscribePartial: text)
    }

    func speechEngineDidFinishTranscription(_ text: String) {
        handleFinishedTranscription(text)
    }

    func speechEngineDidChangeListeningState(_ isListening: Bool) {
        // Internal state tracking — external state managed via `state` property
    }

    func speechEngineDidEncounterError(_ error: VoiceControlError) {
        delegate?.voiceControl(self, didEncounterError: error)
    }
}
