import AppKit
import Foundation

// MARK: - Shared Test Helpers

/// Creates a minimal valid PNG image data for testing.
/// Used across multiple heatmap test suites to create floor plan image data.
func makeTestPNGData(width: Int = 100, height: Int = 80) -> Data {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ), let cgImage = context.makeImage()
    else {
        return Data()
    }
    let rep = NSBitmapImageRep(cgImage: cgImage)
    return rep.representation(using: .png, properties: [:]) ?? Data()
}

/// Writes test PNG data to a temporary file and returns the URL.
/// Used across multiple heatmap test suites to create floor plan image files.
func makeTestPNGFile(name: String = "test_floorplan.png", width: Int = 100, height: Int = 80) -> URL {
    let data = makeTestPNGData(width: width, height: height)
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
    try? data.write(to: url)
    return url
}

/// Writes test data to a temporary file with the given name.
/// Useful for creating files with specific extensions for import testing.
func makeTestFile(name: String, data: Data = Data([0x00, 0x01, 0x02])) -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
    try? data.write(to: url)
    return url
}
