import Foundation

/// Download lifecycle state.
public enum DownloadState: Sendable, Equatable {
    /// No download in progress or completed.
    case idle

    /// Download is actively receiving data.
    case downloading

    /// Download was paused by the user.
    case paused

    /// Download completed successfully.
    case completed

    /// Download failed.
    case failed(String)
}
