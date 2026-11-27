import CoreGraphics
import Foundation
import UIKit

/// A view model that reads a photo the user takes or chooses: label capture (#456) and modem
/// lights (#558). The shared steps turn the photo into an upright image or an error; each model
/// says how it shows loading and failure, and what it reads.
@MainActor
protocol PhotoReading: AnyObject {
    /// The photo is loading: clear any earlier error and show progress.
    func photoLoading()
    /// The photo couldn't be opened: back to choosing one, with `message`.
    func photoFailed(_ message: String)
    func read(_ image: CGImage) async
}

extension PhotoReading {
    /// Reads a photo from the library; `load` returns its data, or nil when Photos can't.
    func readPhoto(_ load: @Sendable () async -> Data?) async {
        photoLoading()
        guard let data = await load(), let image = await UprightPhoto.image(data: data) else {
            photoFailed("That photo couldn't be opened. Try another one.")
            return
        }
        await read(image)
    }

    /// Reads a photo from the camera.
    func readCameraPhoto(_ photo: UIImage) async {
        photoLoading()
        guard let image = await UprightPhoto.image(photo) else {
            photoFailed("That photo couldn't be opened. Try again.")
            return
        }
        await read(image)
    }
}

/// Photos as Vision and the on-device model should see them: upright, and no larger than they
/// need. Drawn off the main actor; a 12-megapixel photo takes a moment.
enum UprightPhoto {
    static let maxDimension: CGFloat = 2048

    static func image(data: Data) async -> CGImage? {
        await Task.detached(priority: .userInitiated) {
            UIImage(data: data).flatMap(draw)
        }.value
    }

    static func image(_ image: UIImage) async -> CGImage? {
        await Task.detached(priority: .userInitiated) {
            draw(image)
        }.value
    }

    nonisolated private static func draw(_ image: UIImage) -> CGImage? {
        let scale = min(1, maxDimension / max(image.size.width, image.size.height, 1))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        guard size.width >= 1, size.height >= 1 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }.cgImage
    }
}
