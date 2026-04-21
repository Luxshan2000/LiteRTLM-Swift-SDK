import Foundation

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

enum ImageUtilities {

    /// Resize image data to fit within maxDimension, return JPEG-encoded bytes.
    static func prepareForVision(_ data: Data, maxDimension: Int) throws -> Data {
        #if canImport(UIKit)
        guard let image = UIImage(data: data) else {
            throw LiteRTLMError.imageProcessingFailed
        }
        let size = image.size
        let scale = min(
            CGFloat(maxDimension) / max(size.width, size.height),
            1.0
        )
        if scale < 1.0 {
            let newSize = CGSize(
                width: size.width * scale,
                height: size.height * scale
            )
            let renderer = UIGraphicsImageRenderer(size: newSize)
            let resized = renderer.image { _ in
                image.draw(in: CGRect(origin: .zero, size: newSize))
            }
            guard let jpeg = resized.jpegData(compressionQuality: 0.85) else {
                throw LiteRTLMError.imageProcessingFailed
            }
            return jpeg
        }
        guard let jpeg = image.jpegData(compressionQuality: 0.85) else {
            throw LiteRTLMError.imageProcessingFailed
        }
        return jpeg

        #elseif canImport(AppKit)
        guard let image = NSImage(data: data) else {
            throw LiteRTLMError.imageProcessingFailed
        }
        guard let cgImage = image.cgImage(
            forProposedRect: nil, context: nil, hints: nil
        ) else {
            throw LiteRTLMError.imageProcessingFailed
        }
        let size = CGSize(width: cgImage.width, height: cgImage.height)
        let scale = min(
            CGFloat(maxDimension) / max(size.width, size.height),
            1.0
        )
        let newSize = CGSize(
            width: size.width * scale,
            height: size.height * scale
        )
        let bitmapRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(newSize.width),
            pixelsHigh: Int(newSize.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmapRep)
        NSGraphicsContext.current?.imageInterpolation = .high
        let rect = NSRect(origin: .zero, size: newSize)
        image.draw(in: rect)
        NSGraphicsContext.restoreGraphicsState()

        guard let jpeg = bitmapRep.representation(
            using: .jpeg, properties: [.compressionFactor: 0.85]
        ) else {
            throw LiteRTLMError.imageProcessingFailed
        }
        return jpeg
        #else
        return data
        #endif
    }
}
