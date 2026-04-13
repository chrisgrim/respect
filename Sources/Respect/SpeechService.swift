import Foundation
import Speech
import AVFoundation

@MainActor
class SpeechService: ObservableObject {
    @Published var isRecording = false
    @Published var transcript = ""

    private var speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine = AVAudioEngine()

    init() {
        // Request both permissions up front
        SFSpeechRecognizer.requestAuthorization { _ in }
        AVCaptureDevice.requestAccess(for: .audio) { _ in }
    }

    private var isAuthorized: Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    func startRecording() {
        guard !isRecording else { return }

        // Check permissions live each time
        guard isAuthorized else {
            print("Speech not authorized: \(SFSpeechRecognizer.authorizationStatus().rawValue)")
            return
        }

        // Cancel any in-progress task
        recognitionTask?.cancel()
        recognitionTask = nil

        transcript = ""
        isRecording = true

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            print("Audio engine failed to start: \(error)")
            isRecording = false
            return
        }

        recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                }
                if error != nil || (result?.isFinal ?? false) {
                    if self.isRecording {
                        self.stopRecording()
                    }
                }
            }
        }
    }

    func stopRecording() {
        guard isRecording else { return }

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask = nil
        isRecording = false
    }
}
