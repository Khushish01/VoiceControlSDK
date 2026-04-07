import Foundation
import Speech
import AVFoundation

protocol SpeechRecognitionEngineDelegate: AnyObject {
    func speechEngineDidDetectWakeWord(actionId: String?)
    func speechEngineDidTranscribePartial(_ text: String)
    func speechEngineDidFinishTranscription(_ text: String)
    func speechEngineDidChangeListeningState(_ isListening: Bool)
    func speechEngineDidEncounterError(_ error: VoiceControlError)
}

enum SpeechListeningMode {
    case passive
    case active
}

/// Core speech recognition engine using Apple Speech framework.
/// Supports two-stage listening: passive (wake word) and active (full command).
final class SpeechRecognitionEngine: NSObject {

    weak var delegate: SpeechRecognitionEngineDelegate?

    private let interpreter: CommandInterpreterEngine
    private let silenceTimeout: TimeInterval

    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    private var currentLocale: String
    private var listeningMode: SpeechListeningMode = .passive
    private var silenceTimer: Timer?
    private var passiveRestartTimer: Timer?
    private var isPaused: Bool = false
    private var isIntentionallyStopping: Bool = false
    private var contextualStrings: [String] = []

    var isListening: Bool { audioEngine.isRunning }

    init(interpreter: CommandInterpreterEngine, silenceTimeout: TimeInterval, initialLocale: String, contextualStrings: [String] = []) {
        self.interpreter = interpreter
        self.silenceTimeout = silenceTimeout
        self.currentLocale = initialLocale
        self.contextualStrings = contextualStrings
        self.speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: initialLocale))
        super.init()
    }

    func setContextualStrings(_ strings: [String]) {
        self.contextualStrings = strings
    }

    // MARK: - Permissions

    func requestPermissions(completion: @escaping (Bool) -> Void) {
        var micGranted = false
        var speechGranted = false
        let group = DispatchGroup()

        group.enter()
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            micGranted = granted
            group.leave()
        }

        group.enter()
        SFSpeechRecognizer.requestAuthorization { status in
            speechGranted = (status == .authorized)
            group.leave()
        }

        group.notify(queue: .main) {
            completion(micGranted && speechGranted)
        }
    }

    // MARK: - Language

    func setLocale(_ locale: String) {
        let wasListening = isListening
        let mode = listeningMode
        if wasListening { stopListening() }
        currentLocale = locale
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: locale))
        if wasListening { startListening(mode: mode) }
    }

    // MARK: - Listening Control

    func startListening(mode: SpeechListeningMode) {
        guard !isPaused else { return }
        isIntentionallyStopping = false
        listeningMode = mode
        passiveRestartTimer?.invalidate()
        passiveRestartTimer = nil
        if audioEngine.isRunning { stopListening() }
        if speechRecognizer == nil {
            speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: currentLocale))
        }
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            delegate?.speechEngineDidEncounterError(.recognizerUnavailable)
            return
        }
        do {
            try startRecognition()
            delegate?.speechEngineDidChangeListeningState(true)
            // In passive mode, periodically restart the session so the transcript
            // doesn't accumulate endlessly and wake-word matching stays clean.
            if mode == .passive {
                startPassiveRestartTimer()
            }
        } catch {
            delegate?.speechEngineDidEncounterError(.audioEngineFailure(error))
        }
    }

    func stopListening() {
        isIntentionallyStopping = true
        silenceTimer?.invalidate()
        silenceTimer = nil
        passiveRestartTimer?.invalidate()
        passiveRestartTimer = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        if audioEngine.isRunning { audioEngine.stop() }
        audioEngine.inputNode.removeTap(onBus: 0)
        delegate?.speechEngineDidChangeListeningState(false)
    }

    func pauseListening() {
        isPaused = true
        if isListening { stopListening() }
    }

    func resumeListening(mode: SpeechListeningMode? = nil) {
        isPaused = false
        isIntentionallyStopping = false
        startListening(mode: mode ?? listeningMode)
    }

    // MARK: - Private

    private func startRecognition() throws {
        recognitionTask?.cancel()
        recognitionTask = nil

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else { return }

        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.requiresOnDeviceRecognition = speechRecognizer?.supportsOnDeviceRecognition ?? false
        if !contextualStrings.isEmpty {
            recognitionRequest.contextualStrings = contextualStrings
        }

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }

            if let result = result {
                let transcript = result.bestTranscription.formattedString
                DispatchQueue.main.async { self.delegate?.speechEngineDidTranscribePartial(transcript) }

                if self.listeningMode == .passive {
                    let wakeResult = self.interpreter.isWakeWord(transcript, locale: self.currentLocale)
                    if wakeResult.detected {
                        self.stopListening()
                        DispatchQueue.main.async {
                            self.delegate?.speechEngineDidDetectWakeWord(actionId: wakeResult.actionId)
                        }
                        return
                    }
                } else {
                    self.resetSilenceTimer(currentTranscript: transcript)
                }

                if result.isFinal { self.handleFinalResult(transcript) }
            }

            if let error = error {
                let nsError = error as NSError
                let benignCodes = [216, 1110, 301, 4]
                if benignCodes.contains(nsError.code) || self.isPaused || self.isIntentionallyStopping {
                    if !self.isPaused && !self.isIntentionallyStopping { self.restartListening() }
                    return
                }
                self.stopListening()
                DispatchQueue.main.async {
                    self.delegate?.speechEngineDidEncounterError(.recognitionFailed(error))
                }
            }
        }
    }

    private func handleFinalResult(_ transcript: String) {
        silenceTimer?.invalidate()
        silenceTimer = nil
        if listeningMode == .active {
            stopListening()
            DispatchQueue.main.async { self.delegate?.speechEngineDidFinishTranscription(transcript) }
        } else {
            restartListening()
        }
    }

    private func restartListening() {
        guard !isPaused, !isIntentionallyStopping else { return }
        let mode = listeningMode
        // Use internal cleanup without setting isIntentionallyStopping
        silenceTimer?.invalidate()
        silenceTimer = nil
        passiveRestartTimer?.invalidate()
        passiveRestartTimer = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        if audioEngine.isRunning { audioEngine.stop() }
        audioEngine.inputNode.removeTap(onBus: 0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self = self, !self.isPaused, !self.isIntentionallyStopping else { return }
            self.startListening(mode: mode)
        }
    }

    private func resetSilenceTimer(currentTranscript: String) {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceTimeout, repeats: false) { [weak self] _ in
            self?.handleFinalResult(currentTranscript)
        }
    }

    /// Periodically restarts the passive recognition session so the transcript
    /// doesn't keep accumulating across multiple spoken phrases.
    private func startPassiveRestartTimer() {
        passiveRestartTimer?.invalidate()
        passiveRestartTimer = Timer.scheduledTimer(withTimeInterval: 8.0, repeats: false) { [weak self] _ in
            guard let self = self, self.listeningMode == .passive, !self.isPaused, !self.isIntentionallyStopping else { return }
            self.restartListening()
        }
    }
}
