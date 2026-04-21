import Foundation
import os.log

/// Downloads and manages `.litertlm` model files on disk.
///
/// Observable for SwiftUI integration. Supports pause, resume, and cancel.
///
/// ```swift
/// let downloader = ModelDownloader()
///
/// // Download default model
/// await downloader.download(model: .gemma4E2B)
///
/// // Or download from custom URL
/// await downloader.download(from: myModelURL, fileName: "custom.litertlm")
///
/// // Check progress
/// print(downloader.progress) // 0.0 ... 1.0
///
/// // Use the model
/// if let path = downloader.modelPath(for: .gemma4E2B) {
///     let config = EngineConfiguration(modelPath: path)
/// }
/// ```
@Observable
public final class ModelDownloader: @unchecked Sendable {

    // MARK: - Public State

    /// Current download state.
    public private(set) var state: DownloadState = .idle

    /// Download progress (0.0 to 1.0).
    public private(set) var progress: Double = 0.0

    /// Bytes downloaded so far.
    public private(set) var downloadedBytes: Int64 = 0

    /// Total expected bytes (nil if unknown).
    public private(set) var totalBytes: Int64?

    // MARK: - Private

    private let lock = NSLock()
    private var downloadTask: URLSessionDownloadTask?
    private var session: URLSession?
    private var sessionDelegate: DownloadDelegate?
    private var resumeData: Data?
    private let logger = Logger(subsystem: "com.litertlm", category: "downloader")

    /// Base directory for storing models.
    public let modelsDirectory: URL

    // MARK: - Init

    public init(modelsDirectory: URL? = nil) {
        if let dir = modelsDirectory {
            self.modelsDirectory = dir
        } else {
            let appSupport = FileManager.default.urls(
                for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.modelsDirectory = appSupport.appendingPathComponent(
                "LiteRTLM/Models", isDirectory: true)
        }

        try? FileManager.default.createDirectory(
            at: self.modelsDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Query

    /// Check if a model is already downloaded.
    public func isDownloaded(_ model: ModelInfo) -> Bool {
        FileManager.default.fileExists(
            atPath: modelsDirectory.appendingPathComponent(model.fileName).path)
    }

    /// Check if a file exists by name.
    public func isDownloaded(fileName: String) -> Bool {
        FileManager.default.fileExists(
            atPath: modelsDirectory.appendingPathComponent(fileName).path)
    }

    /// Get the local path for a downloaded model.
    public func modelPath(for model: ModelInfo) -> URL? {
        let path = modelsDirectory.appendingPathComponent(model.fileName)
        return FileManager.default.fileExists(atPath: path.path) ? path : nil
    }

    /// Get the local path by file name.
    public func modelPath(fileName: String) -> URL? {
        let path = modelsDirectory.appendingPathComponent(fileName)
        return FileManager.default.fileExists(atPath: path.path) ? path : nil
    }

    // MARK: - Download

    /// Download a model from the registry.
    public func download(model: ModelInfo) async {
        await download(from: model.url, fileName: model.fileName, expectedSize: model.expectedSize)
    }

    /// Download a model from a custom URL.
    public func download(
        from url: URL,
        fileName: String? = nil,
        expectedSize: Int64? = nil
    ) async {
        let targetName = fileName ?? url.lastPathComponent

        // Check if already downloaded
        if isDownloaded(fileName: targetName) {
            state = .completed
            progress = 1.0
            return
        }

        totalBytes = expectedSize
        state = .downloading

        let delegate = DownloadDelegate { [weak self] bytesWritten, totalWritten, expectedTotal in
            guard let self else { return }
            lock.lock()
            downloadedBytes = totalWritten
            if expectedTotal > 0 {
                totalBytes = expectedTotal
                progress = Double(totalWritten) / Double(expectedTotal)
            } else if let expected = expectedSize {
                progress = Double(totalWritten) / Double(expected)
            }
            lock.unlock()
        }

        sessionDelegate = delegate
        let urlSession = URLSession(
            configuration: .default, delegate: delegate, delegateQueue: nil)
        session = urlSession

        let task: URLSessionDownloadTask
        if let resumeData {
            task = urlSession.downloadTask(withResumeData: resumeData)
            self.resumeData = nil
        } else {
            task = urlSession.downloadTask(with: url)
        }
        downloadTask = task

        await withCheckedContinuation { continuation in
            delegate.completion = { [weak self] result in
                guard let self else {
                    continuation.resume()
                    return
                }
                switch result {
                case .success(let tempURL):
                    let dest = modelsDirectory.appendingPathComponent(targetName)
                    do {
                        if FileManager.default.fileExists(atPath: dest.path) {
                            try FileManager.default.removeItem(at: dest)
                        }
                        try FileManager.default.moveItem(at: tempURL, to: dest)
                        state = .completed
                        progress = 1.0
                        logger.info("Model downloaded to \(dest.path)")
                    } catch {
                        state = .failed("Failed to move file: \(error.localizedDescription)")
                        logger.error("Move failed: \(error.localizedDescription)")
                    }
                case .failure(let error):
                    if (error as NSError).code == NSURLErrorCancelled {
                        // Paused or cancelled — don't set failed
                        if state != .paused {
                            state = .idle
                        }
                    } else {
                        state = .failed(error.localizedDescription)
                        logger.error("Download failed: \(error.localizedDescription)")
                    }
                }
                continuation.resume()
            }
            task.resume()
        }
    }

    // MARK: - Control

    /// Pause the active download (resume data is preserved).
    public func pause() {
        downloadTask?.cancel(byProducingResumeData: { [weak self] data in
            self?.lock.lock()
            self?.resumeData = data
            self?.state = .paused
            self?.lock.unlock()
        })
    }

    /// Cancel the download and discard resume data.
    public func cancel() {
        downloadTask?.cancel()
        downloadTask = nil
        resumeData = nil
        state = .idle
        progress = 0
        downloadedBytes = 0
        totalBytes = nil
    }

    /// Delete a downloaded model from disk.
    public func deleteModel(_ model: ModelInfo) throws {
        try deleteModel(fileName: model.fileName)
    }

    /// Delete a model file by name.
    public func deleteModel(fileName: String) throws {
        let path = modelsDirectory.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: path.path) {
            try FileManager.default.removeItem(at: path)
        }
        state = .idle
        progress = 0
    }
}

// MARK: - URLSession Delegate

private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, Sendable {

    let onProgress: @Sendable (Int64, Int64, Int64) -> Void
    nonisolated(unsafe) var completion: ((Result<URL, Error>) -> Void)?

    init(onProgress: @escaping @Sendable (Int64, Int64, Int64) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // Copy to a temp location that won't be cleaned up
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".litertlm")
        do {
            try FileManager.default.copyItem(at: location, to: tmp)
            completion?(.success(tmp))
        } catch {
            completion?(.failure(error))
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        onProgress(bytesWritten, totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error {
            completion?(.failure(error))
        }
    }
}
