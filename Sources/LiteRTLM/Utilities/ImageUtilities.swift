import Foundation
import UIKit

enum ImageUtilities {

    /// Resize image data to fit within maxDimension, return JPEG-encoded bytes.
    static func prepareForVision(_ data: Data, maxDimension: Int) throws -> Data {
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
    }
}
