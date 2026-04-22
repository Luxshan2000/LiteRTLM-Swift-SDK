import Foundation
import AVFoundation

@Observable
final class SpeechService {
    var isRecording = false
    var errorMessage: String?
    private(set) var recordedAudioData: Data?

    private var audioRecorder: AVAudioRecorder?
    private var recordingURL: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("voice_input.wav")
    }

    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    func startRecording() {
        guard !isRecording else { return }

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .default, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            errorMessage = "Audio session error: \(error.localizedDescription)"
            return
        }

        // Record as WAV (Linear PCM) — the format Gemma expects
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]

        do {
            // Remove old recording
            try? FileManager.default.removeItem(at: recordingURL)

            audioRecorder = try AVAudioRecorder(url: recordingURL, settings: settings)
            audioRecorder?.record()
            isRecording = true
            recordedAudioData = nil
        } catch {
            errorMessage = "Recording error: \(error.localizedDescription)"
        }
    }

    func stopRecording() -> Data? {
        guard isRecording else { return nil }

        audioRecorder?.stop()
        audioRecorder = nil
        isRecording = false

        // Read the recorded WAV file
        guard let data = try? Data(contentsOf: recordingURL) else {
            errorMessage = "Failed to read recorded audio"
            return nil
        }

        recordedAudioData = data
        try? FileManager.default.removeItem(at: recordingURL)
        return data
    }
}
