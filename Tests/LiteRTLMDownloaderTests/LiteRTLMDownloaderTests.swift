import XCTest
@testable import LiteRTLMDownloader

final class LiteRTLMDownloaderTests: XCTestCase {

    func testModelRegistryGemma4E2B() {
        let model = ModelRegistry.gemma4E2B
        XCTAssertEqual(model.name, "gemma-4-e2b")
        XCTAssertFalse(model.fileName.isEmpty)
        XCTAssertNotNil(model.expectedSize)
    }

    func testDownloadStateEquality() {
        XCTAssertEqual(DownloadState.idle, DownloadState.idle)
        XCTAssertEqual(DownloadState.downloading, DownloadState.downloading)
        XCTAssertEqual(DownloadState.completed, DownloadState.completed)
        XCTAssertNotEqual(DownloadState.idle, DownloadState.completed)
    }

    func testModelDownloaderInitialization() {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-models-\(UUID().uuidString)")
        let downloader = ModelDownloader(modelsDirectory: tmpDir)
        XCTAssertEqual(downloader.modelsDirectory, tmpDir)
        XCTAssertFalse(downloader.isDownloaded(ModelRegistry.gemma4E2B))

        // Cleanup
        try? FileManager.default.removeItem(at: tmpDir)
    }

    func testModelPathReturnsNilWhenNotDownloaded() {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-models-\(UUID().uuidString)")
        let downloader = ModelDownloader(modelsDirectory: tmpDir)
        XCTAssertNil(downloader.modelPath(for: ModelRegistry.gemma4E2B))

        try? FileManager.default.removeItem(at: tmpDir)
    }

    func testModelInfoIdentifiable() {
        let model = ModelRegistry.gemma4E2B
        XCTAssertEqual(model.id, model.name)
    }
}
