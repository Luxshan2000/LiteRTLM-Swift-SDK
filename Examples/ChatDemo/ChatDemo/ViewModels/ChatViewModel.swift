import Foundation
import SwiftUI
import LiteRTLM
import LiteRTLMDownloader

@Observable
@MainActor
final class ChatViewModel {

    // MARK: - State

    var messages: [ChatMessage] = []
    var inputText = ""
    var isGenerating = false
    var isModelLoading = false
    var modelReady = false
    var downloadProgress: Double = 0
    var downloadedBytes: Int64 = 0
    var totalBytes: Int64 = 0
    var downloadSpeed: Double = 0
    var estimatedTimeLeft: String = ""
    var statusMessage = "Tap 'Load Model' to start"
    var errorMessage: String?
    var pendingImage: Data?
    var pendingAudio: Data?
    var showPhotoPicker = false
    var showCamera = false
    var showAudioPicker = false

    // MARK: - Services

    let speech = SpeechService()

    // MARK: - Private

    private var engine: LMEngine?
    private var session: LMSession?
    private let downloader = ModelDownloader()
    private var generationTask: Task<Void, Never>?

    /// Tags that Gemma emits which should not be shown to the user.
    private static let stripTags = [
        "<end_of_turn>", "<start_of_turn>", "<eos>", "<bos>",
        "<|channel>", "<channel|>", "<|think|>",
        "<start_of_turn>model", "<start_of_turn>user",
    ]

    private static let systemPrompt = """
    You are a helpful, friendly AI assistant running entirely on-device via \
    LiteRTLM Swift SDK and Google's Gemma 4. You are part of a demo app that \
    showcases on-device LLM inference. Be concise, helpful, and conversational. \
    You can see images the user sends. Keep responses short unless asked for detail.
    """

    // MARK: - Model Lifecycle

    func loadModel() async {
        guard !isModelLoading && !modelReady else { return }
        isModelLoading = true
        errorMessage = nil

        // Step 1: Download if needed
        if !downloader.isDownloaded(ModelRegistry.gemma4E2B) {
            statusMessage = "Downloading model..."
            totalBytes = ModelRegistry.gemma4E2B.expectedSize ?? 0

            let downloadTask = Task { await downloader.download(model: ModelRegistry.gemma4E2B) }

            var lastBytes: Int64 = 0
            var lastTime = Date()

            while !downloadTask.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard downloader.state == .downloading else { break }

                let now = Date()
                let currentBytes = downloader.downloadedBytes
                let elapsed = now.timeIntervalSince(lastTime)

                if elapsed > 0 {
                    let bytesInInterval = currentBytes - lastBytes
                    let instantSpeed = Double(bytesInInterval) / elapsed
                    downloadSpeed = downloadSpeed == 0 ? instantSpeed : downloadSpeed * 0.7 + instantSpeed * 0.3
                    lastBytes = currentBytes
                    lastTime = now
                }

                downloadProgress = downloader.progress
                downloadedBytes = currentBytes
                if let total = downloader.totalBytes { totalBytes = total }

                if downloadSpeed > 0 {
                    let remaining = Double(totalBytes - currentBytes)
                    let seconds = Int(remaining / downloadSpeed)
                    estimatedTimeLeft = Self.formatDuration(seconds)
                }

                statusMessage = "\(Self.formatBytes(currentBytes)) / \(Self.formatBytes(totalBytes))  •  \(Self.formatBytes(Int64(downloadSpeed)))/s  •  \(estimatedTimeLeft) left"
            }

            await downloadTask.value

            if case .failed(let msg) = downloader.state {
                errorMessage = "Download failed: \(msg)"
                isModelLoading = false
                return
            }
        }

        guard let modelPath = downloader.modelPath(for: ModelRegistry.gemma4E2B) else {
            errorMessage = "Model file not found after download"
            isModelLoading = false
            return
        }

        // Validate file size
        let attrs = try? FileManager.default.attributesOfItem(atPath: modelPath.path)
        let fileSize = (attrs?[.size] as? Int64) ?? 0
        if fileSize < 500_000_000 {
            try? FileManager.default.removeItem(at: modelPath)
            errorMessage = "Downloaded file is invalid (\(fileSize) bytes). Deleted — tap Load Model to retry."
            isModelLoading = false
            return
        }

        // Step 2: Load engine
        statusMessage = "Loading model into memory..."
        let config = EngineConfiguration(modelPath: modelPath)
            .backend(.cpu)
            .logLevel(.warning)

        let newEngine = LMEngine(configuration: config)

        do {
            try await newEngine.load()
            engine = newEngine

            // Step 3: Create session
            statusMessage = "Creating session..."
            let sessionConfig = SessionConfiguration()
                .maxOutputTokens(1024)
                .sampler(.greedy)
            session = try await newEngine.createSession(configuration: sessionConfig)

            modelReady = true
            statusMessage = "Ready"

            // Prime the session with system prompt
            messages.append(ChatMessage(
                role: .system,
                text: "Ready to chat. Send a message, photo, or use voice.",
                image: nil
            ))
        } catch {
            errorMessage = "Failed to load: \(error.localizedDescription)"
            statusMessage = "Load failed"
        }

        isModelLoading = false
    }

    // MARK: - Send Message

    func send() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || pendingImage != nil else { return }
        guard modelReady, let session else {
            errorMessage = "Model not loaded"
            return
        }

        let imageData = pendingImage
        pendingImage = nil

        let userMessage = ChatMessage(
            role: .user,
            text: text.isEmpty ? "[Photo]" : text,
            image: imageData
        )
        messages.append(userMessage)
        inputText = ""

        let placeholder = ChatMessage(role: .model, text: "", image: nil)
        messages.append(placeholder)
        let responseIndex = messages.count - 1

        isGenerating = true

        generationTask = Task {
            do {
                let prompt = Self.systemPrompt + "\n" + (text.isEmpty
                    ? "Describe what you see in this image in detail."
                    : text)

                if let imageData {
                    let response = try await session.generate(
                        text: prompt,
                        images: [imageData]
                    )
                    if !Task.isCancelled {
                        messages[responseIndex].text = Self.stripGemmaTags(response)
                    }
                } else {
                    let stream = session.generateStream(prompt)
                    var buffer = ""
                    for try await token in stream {
                        if Task.isCancelled { break }
                        buffer += token
                        messages[responseIndex].text = Self.stripGemmaTags(buffer)
                    }
                }
            } catch {
                if !Task.isCancelled {
                    messages[responseIndex].text = "Error: \(error.localizedDescription)"
                }
            }

            isGenerating = false
            generationTask = nil
        }
    }

    // MARK: - Stop

    func stopGenerating() {
        generationTask?.cancel()
        generationTask = nil
        isGenerating = false
    }

    // MARK: - Voice

    func toggleVoice() async {
        if speech.isListening {
            speech.stopListening()
            if !speech.transcript.isEmpty {
                inputText = speech.transcript
            }
        } else {
            let authorized = await speech.requestPermission()
            if authorized {
                speech.startListening()
            } else {
                errorMessage = "Microphone permission denied"
            }
        }
    }

    // MARK: - Cleanup

    func cleanup() {
        stopGenerating()
        session?.close()
        session = nil
        Task { await engine?.unload() }
        engine = nil
        modelReady = false
        messages.removeAll()
        downloadProgress = 0
        downloadedBytes = 0
        downloadSpeed = 0
        estimatedTimeLeft = ""
        statusMessage = "Tap 'Load Model' to start"
    }

    // MARK: - Gemma Tag Stripping

    private static func stripGemmaTags(_ text: String) -> String {
        var result = text
        for tag in stripTags {
            result = result.replacingOccurrences(of: tag, with: "")
        }
        // Strip thinking blocks: <|channel>...<channel|>
        while let start = result.range(of: "<|channel>"),
              let end = result.range(of: "<channel|>", range: start.upperBound..<result.endIndex) {
            result.removeSubrange(start.lowerBound..<end.upperBound)
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Formatting

    static func formatBytes(_ bytes: Int64) -> String {
        let abs = abs(bytes)
        switch abs {
        case 0..<1_024:
            return "\(abs) B"
        case 1_024..<1_048_576:
            return String(format: "%.1f KB", Double(abs) / 1_024)
        case 1_048_576..<1_073_741_824:
            return String(format: "%.1f MB", Double(abs) / 1_048_576)
        default:
            return String(format: "%.2f GB", Double(abs) / 1_073_741_824)
        }
    }

    static func formatDuration(_ totalSeconds: Int) -> String {
        if totalSeconds < 60 { return "\(totalSeconds)s" }
        let m = totalSeconds / 60
        let s = totalSeconds % 60
        if m < 60 { return "\(m)m \(s)s" }
        let h = m / 60
        return "\(h)h \(m % 60)m"
    }
}
