import Foundation

/// A piece of content that can be sent to the model.
///
/// ```swift
/// let text = Content.text("Describe this image")
/// let image = Content.image(jpegData)
/// let audio = Content.audio(wavData, format: .wav)
/// ```
public enum Content: Sendable {
    case text(String)
    case image(Data, maxDimension: Int = 1024)
    case audio(Data, format: AudioFormat)
}

/// Supported audio formats for multimodal input.
public enum AudioFormat: String, Sendable {
    case wav = "wav"
    case flac = "flac"
    case mp3 = "mp3"
}

/// A role in the conversation.
public enum Role: String, Sendable, Codable {
    case user
    case model
    case system
    case tool
}

/// A message in a conversation consisting of a role and content parts.
public struct Message: Sendable {
    public let role: Role
    public let content: [Content]

    public init(role: Role, content: [Content]) {
        self.role = role
        self.content = content
    }

    /// Convenience for a simple text message.
    public static func user(_ text: String) -> Message {
        Message(role: .user, content: [.text(text)])
    }

    /// Convenience for a model response (used for history construction).
    public static func model(_ text: String) -> Message {
        Message(role: .model, content: [.text(text)])
    }

    /// Convenience for system prompt.
    public static func system(_ text: String) -> Message {
        Message(role: .system, content: [.text(text)])
    }
}
