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

    /// Gemma 4 E2B multimodal (~2.6 GB).
    public static let gemma4E2B = ModelInfo(
        name: "gemma-4-e2b",
        displayName: "Gemma 4 E2B",
        url: URL(string: "https://huggingface.co/litert-community/Gemma3-E2B-it/resolve/main/gemma3-E2B-it-int8.litertlm")!,
        expectedSize: 2_800_000_000,
        fileName: "gemma3-E2B-it-int8.litertlm"
    )
}
