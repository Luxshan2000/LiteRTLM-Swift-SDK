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
    var statusMessage = "Tap 'Load Model' to start"
    var errorMessage: String?
    var pendingImage: Data?

    // MARK: - Services

    let speech = SpeechService()

    // MARK: - Private

    private var engine: LMEngine?
    private var session: LMSession?
    private let downloader = ModelDownloader()

    // MARK: - Model Lifecycle

    func loadModel() async {
        guard !isModelLoading && !modelReady else { return }
        isModelLoading = true
        errorMessage = nil

        // Step 1: Download if needed
        if !downloader.isDownloaded(ModelRegistry.gemma4E2B) {
            statusMessage = "Downloading model..."
            await downloader.download(model: .gemma4E2B)

            // Track progress
            while downloader.state == .downloading {
                downloadProgress = downloader.progress
                statusMessage = "Downloading... \(Int(downloadProgress * 100))%"
                try? await Task.sleep(for: .milliseconds(200))
            }

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

        // Step 2: Load engine
        statusMessage = "Loading model into memory..."
        let config = EngineConfiguration(modelPath: modelPath)
            .backend(.gpu)
            .logLevel(.warning)

        let newEngine = LMEngine(configuration: config)

        do {
            try await newEngine.load()
            engine = newEngine

            // Step 3: Create session
            statusMessage = "Creating session..."
            let sessionConfig = SessionConfiguration()
                .maxOutputTokens(1024)
                .sampler(.balanced)
            session = try await newEngine.createSession(configuration: sessionConfig)

            modelReady = true
            statusMessage = "Ready"
            messages.append(ChatMessage(
                role: .system,
                text: "Model loaded. Send a message, photo, or use voice input.",
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

        // Add user message
        let userMessage = ChatMessage(
            role: .user,
            text: text.isEmpty ? "[Photo]" : text,
            image: imageData
        )
        messages.append(userMessage)
        inputText = ""

        // Add placeholder for model response
        let placeholder = ChatMessage(role: .model, text: "", image: nil)
        messages.append(placeholder)
        let responseIndex = messages.count - 1

        isGenerating = true

        do {
            // Build prompt — for images, describe via vision prompt wrapping
            let prompt: String
            if imageData != nil {
                prompt = text.isEmpty
                    ? "Describe what you see in this image in detail."
                    : text
                // Note: For actual vision, you'd use LMConversation.send(images:)
                // This demo uses text session, so we note the image was attached
                messages[responseIndex].text = "[Vision requires Conversation API — using text mode]\n\n"
            } else {
                prompt = text
            }

            let stream = session.generateStream(prompt)
            for try await token in stream {
                messages[responseIndex].text += token
            }
        } catch {
            messages[responseIndex].text = "Error: \(error.localizedDescription)"
        }

        isGenerating = false
    }

    // MARK: - Voice

    func toggleVoice() async {
        if speech.isListening {
            speech.stopListening()
            // Transfer transcript to input
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
        session?.close()
        session = nil
        Task {
            await engine?.unload()
        }
        engine = nil
        modelReady = false
        messages.removeAll()
        statusMessage = "Tap 'Load Model' to start"
    }
}
