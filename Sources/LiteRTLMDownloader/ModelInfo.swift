import Foundation

/// Metadata about a downloadable model.
public struct ModelInfo: Sendable, Identifiable {
    public var id: String { name }

    /// Model identifier (e.g. "gemma-4-e2b").
    public let name: String

    /// Human-readable display name.
    public let displayName: String

    /// Download URL.
    public let url: URL

    /// Expected file size in bytes (for progress calculation).
    public let expectedSize: Int64?

    /// File name on disk.
    public let fileName: String

    public init(
        name: String,
        displayName: String,
        url: URL,
        expectedSize: Int64? = nil,
        fileName: String? = nil
    ) {
        self.name = name
        self.displayName = displayName
        self.url = url
        self.expectedSize = expectedSize
        self.fileName = fileName ?? url.lastPathComponent
    }
}

/// Known models available for download.
public enum ModelRegistry {

    /// Gemma 4 E2B instruction-tuned (~2.4 GB).
    public static let gemma4E2B = ModelInfo(
        name: "gemma-4-e2b",
        displayName: "Gemma 4 E2B",
        url: URL(string: "https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm")!,
        expectedSize: 2_583_085_056,
        fileName: "gemma-4-E2B-it.litertlm"
    )

    /// Gemma 4 E4B instruction-tuned (~3.4 GB).
    public static let gemma4E4B = ModelInfo(
        name: "gemma-4-e4b",
        displayName: "Gemma 4 E4B",
        url: URL(string: "https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm/resolve/main/gemma-4-E4B-it.litertlm")!,
        expectedSize: 3_654_467_584,
        fileName: "gemma-4-E4B-it.litertlm"
    )
}
