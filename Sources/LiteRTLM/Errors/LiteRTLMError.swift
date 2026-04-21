import Foundation

/// Typed errors for all LiteRTLM operations.
public enum LiteRTLMError: LocalizedError, Sendable {

    // MARK: - Engine

    /// Engine failed to initialize (bad model path, unsupported backend, etc.).
    case engineCreationFailed(reason: String)

    /// Engine is not loaded — call `engine.load()` first.
    case engineNotReady

    /// Engine is already loaded.
    case engineAlreadyLoaded

    // MARK: - Session

    /// Could not create a session from the engine.
    case sessionCreationFailed

    /// No active session — call `openSession()` first.
    case noActiveSession

    /// A session is already open — close it before opening another.
    case sessionAlreadyOpen

    // MARK: - Conversation

    /// Could not create a conversation.
    case conversationCreationFailed

    /// No active conversation — call `openConversation()` first.
    case noActiveConversation

    /// A conversation is already open.
    case conversationAlreadyOpen

    // MARK: - Generation

    /// The model returned no candidates.
    case emptyResponse

    /// Streaming was interrupted by an error from the C layer.
    case streamingError(message: String)

    /// Generation was cancelled.
    case cancelled

    // MARK: - Input

    /// An input (image, audio, text) could not be prepared.
    case invalidInput(detail: String)

    /// Image could not be resized or encoded.
    case imageProcessingFailed

    /// Audio format is not supported.
    case unsupportedAudioFormat(String)

    // MARK: - Model

    /// Model file not found at the given path.
    case modelNotFound(path: String)

    // MARK: - Internal

    /// Unexpected failure in the C layer.
    case internalError(String)

    // MARK: - LocalizedError

    public var errorDescription: String? {
        switch self {
        case .engineCreationFailed(let reason):
            return "Engine creation failed: \(reason)"
        case .engineNotReady:
            return "Engine is not loaded. Call load() before using."
        case .engineAlreadyLoaded:
            return "Engine is already loaded."
        case .sessionCreationFailed:
            return "Failed to create session."
        case .noActiveSession:
            return "No active session. Call openSession() first."
        case .sessionAlreadyOpen:
            return "A session is already open. Close it first."
        case .conversationCreationFailed:
            return "Failed to create conversation."
        case .noActiveConversation:
            return "No active conversation. Call openConversation() first."
        case .conversationAlreadyOpen:
            return "A conversation is already open. Close it first."
        case .emptyResponse:
            return "Model returned no response."
        case .streamingError(let message):
            return "Streaming error: \(message)"
        case .cancelled:
            return "Generation was cancelled."
        case .invalidInput(let detail):
            return "Invalid input: \(detail)"
        case .imageProcessingFailed:
            return "Failed to process image."
        case .unsupportedAudioFormat(let format):
            return "Unsupported audio format: \(format)"
        case .modelNotFound(let path):
            return "Model not found at: \(path)"
        case .internalError(let msg):
            return "Internal error: \(msg)"
        }
    }
}
