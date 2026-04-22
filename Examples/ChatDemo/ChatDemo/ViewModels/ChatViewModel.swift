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
    var isRecordingVoice: Bool { speech.isRecording }
    var selectedBackend: String = "cpu"  // "cpu" or "gpu"

    // MARK: - Services

    let speech = SpeechService()

    // MARK: - Private

    private var engine: LMEngine?
    private var conversation: LMConversation?
    private let downloader = ModelDownloader()
    private var generationTask: Task<Void, Never>?

    /// Tags that Gemma 4 emits which should not be shown to the user.
    /// Sorted longest-first so compound tags are stripped before their prefixes.
    private static let stripTags: [String] = [
        // Gemma 4 turn markers
        "<|turn>model",
        "<|turn>user",
        "<|turn>system",
        "<|turn>",
        "<turn|>",
        // Gemma 2/3 legacy markers (in case model emits them)
        "<start_of_turn>model",
        "<start_of_turn>user",
        "<start_of_turn>",
        "<end_of_turn>",
        // Thinking / tool tags
        "<|channel>",
        "<channel|>",
        "<|think|>",
        // Special tokens
        "<eos>",
        "<bos>",
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
        let backendChoice: Backend = selectedBackend == "gpu" ? .gpu : .cpu
        statusMessage = "Loading model (\(selectedBackend.uppercased()))..."
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("litertlm_cache")
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        let config = EngineConfiguration(modelPath: modelPath)
            .backend(backendChoice)
            .visionBackend(.cpu)
            .audioBackend(.cpu)
            .maxTokens(4096)
            .cacheDirectory(cacheDir)
            .logLevel(.warning)

        let newEngine = LMEngine(configuration: config)

        do {
            try await newEngine.load()
            engine = newEngine

            // Step 3: Create conversation (handles text + multimodal)
            statusMessage = "Creating session..."
            let convConfig = ConversationConfiguration()
                .maxOutputTokens(1024)
                .sampler(SamplerConfiguration(
                    temperature: 0.7,
                    topK: 40,
                    topP: 0.95,
                    seed: 0,
                    samplerType: .topP
                ))
            conversation = try await newEngine.createConversation(configuration: convConfig)

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
        guard !text.isEmpty || pendingImage != nil || pendingAudio != nil else { return }
        guard modelReady else {
            errorMessage = "Model not loaded"
            return
        }

        let imageData = pendingImage
        let audioData = pendingAudio
        pendingImage = nil
        pendingAudio = nil

        let displayText: String
        if !text.isEmpty { displayText = text }
        else if imageData != nil { displayText = "[Photo]" }
        else { displayText = "[Voice message]" }

        let userMessage = ChatMessage(
            role: .user,
            text: displayText,
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
                let prompt = text.isEmpty
                    ? (imageData != nil ? "Describe what you see in this image."
                       : "Respond to this voice message.")
                    : text

                let hasMedia = imageData != nil || audioData != nil

                guard let conversation else { return }

                if hasMedia {
                    // Multimodal: blocking (vision/audio processing isn't streamable)
                    let response = try await conversation.send(
                        prompt,
                        images: imageData.map { [$0] } ?? [],
                        audio: audioData.map { [$0] } ?? []
                    )
                    if !Task.isCancelled {
                        messages[responseIndex].text = Self.stripGemmaTags(response)
                    }
                } else {
                    // Text: stream token by token
                    let stream = try conversation.sendStream(prompt)
                    var buffer = ""
                    for try await token in stream {
                        if Task.isCancelled { break }
                        buffer += token
                        messages[responseIndex].text = Self.displayText(from: buffer)
                    }
                    if !Task.isCancelled {
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

    // MARK: - Voice (raw audio — passed directly to model)

    func toggleVoice() async {
        if speech.isRecording {
            // Stop recording and attach the raw audio
            if let audioData = speech.stopRecording() {
                pendingAudio = audioData
            }
        } else {
            let authorized = await speech.requestPermission()
            if authorized {
                speech.startRecording()
            } else {
                errorMessage = "Microphone permission denied"
            }
        }
    }

    // MARK: - Cleanup

    func cleanup() {
        stopGenerating()
        conversation?.close()
        conversation = nil
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

    // MARK: - Gemma Tag Handling

    /// For streaming: strip complete tags AND hold back any trailing `<...`
    /// that could be a partial tag still being streamed.
    private static func displayText(from buffer: String) -> String {
        var text = stripGemmaTags(buffer)

        // If text ends with an unclosed `<`, it might be a tag arriving
        // token-by-token (e.g. `<end` → `<end_of` → `<end_of_turn>`).
        // Hold it back so it never flashes in the UI.
        if let lastOpen = text.lastIndex(of: "<") {
            let tail = String(text[lastOpen...])
            // No closing `>` yet — check if it could be the start of a known tag
            if !tail.contains(">") {
                let couldBeTag = stripTags.contains { tag in
                    tag.hasPrefix(tail) || tail.hasPrefix(tag)
                }
                if couldBeTag {
                    text = String(text[..<lastOpen])
                }
            }
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Final pass on completed text: strip all known tags.
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
        // Also strip partial thinking block if stream ended mid-block
        if let start = result.range(of: "<|channel>") {
            result = String(result[..<start.lowerBound])
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
