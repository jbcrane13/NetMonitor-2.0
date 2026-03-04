import AppKit
import CoreGraphics
import os
import UniformTypeIdentifiers

// MARK: - FloorPlanImportError

/// Errors that can occur during floor plan import.
enum FloorPlanImportError: LocalizedError {
    case unsupportedFormat(String)
    case fileReadFailed(String)
    case imageDecodeFailed
    case pdfRenderFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let ext):
            "Unsupported file format: \(ext)"
        case .fileReadFailed(let path):
            "Could not read file at \(path)"
        case .imageDecodeFailed:
            "Failed to decode image data"
        case .pdfRenderFailed:
            "Failed to rasterize PDF page"
        }
    }
}

// MARK: - FloorPlanImportResult

/// The result of importing a floor plan image.
struct FloorPlanImportResult: Sendable {
    let imageData: Data
    let pixelWidth: Int
    let pixelHeight: Int
    let sourceURL: URL
}

// MARK: - FloorPlanImporter

/// Utility for importing floor plan images from various formats.
/// Supports PNG, JPEG, PDF (first page rasterized), and HEIC.
/// Large images are downsampled to keep memory usage reasonable.
enum FloorPlanImporter {

    // MARK: - Constants

    /// Maximum pixel dimension (width or height) for imported images.
    /// Images larger than this are downsampled proportionally.
    static let maxPixelDimension: Int = 4096

    /// Supported UTTypes for the NSOpenPanel filter.
    static let supportedTypes: [UTType] = [
        .png,
        .jpeg,
        .heic,
        .pdf
    ]

    /// File extensions accepted for drag-and-drop validation.
    static let supportedExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "pdf"]

    // MARK: - Import from URL

    /// Imports a floor plan from a file URL, handling format detection,
    /// PDF rasterization, large-image downsampling, and PNG encoding.
    /// - Parameter url: File URL to the floor plan image.
    /// - Returns: A `FloorPlanImportResult` with PNG image data and dimensions.
    static func importFloorPlan(from url: URL) throws -> FloorPlanImportResult {
        let ext = url.pathExtension.lowercased()

        guard supportedExtensions.contains(ext)
        else {
            throw FloorPlanImportError.unsupportedFormat(ext)
        }

        let imageData: Data
        if ext == "pdf" {
            imageData = try rasterizePDF(at: url)
        } else {
            guard let data = try? Data(contentsOf: url)
            else {
                throw FloorPlanImportError.fileReadFailed(url.path)
            }
            imageData = data
        }

        guard let cgImage = createCGImage(from: imageData)
        else {
            throw FloorPlanImportError.imageDecodeFailed
        }

        let downsampled = downsampleIfNeeded(cgImage)
        let pngData = encodePNG(downsampled)

        Logger.app.debug("Floor plan imported: \(downsampled.width)x\(downsampled.height) from \(ext)")

        return FloorPlanImportResult(
            imageData: pngData,
            pixelWidth: downsampled.width,
            pixelHeight: downsampled.height,
            sourceURL: url
        )
    }

    // MARK: - NSOpenPanel

    /// Presents an NSOpenPanel configured for floor plan image selection.
    /// Runs on the main thread. Returns the selected URL, or nil if cancelled.
    @MainActor
    static func presentOpenPanel() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Import Floor Plan"
        panel.prompt = "Import"
        panel.message = "Select a floor plan image (PNG, JPEG, HEIC, or PDF)"
        panel.allowedContentTypes = supportedTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        let response = panel.runModal()
        return response == .OK ? panel.url : nil
    }

    // MARK: - Validation

    /// Checks whether a file URL has a supported extension.
    static func isSupported(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }

    // MARK: - Private Helpers

    /// Rasterizes the first page of a PDF file to bitmap data.
    private static func rasterizePDF(at url: URL) throws -> Data {
        guard let document = CGPDFDocument(url as CFURL),
              let page = document.page(at: 1)
        else {
            throw FloorPlanImportError.pdfRenderFailed
        }

        let mediaBox = page.getBoxRect(.mediaBox)
        let scale: CGFloat = 2.0 // Retina-quality rasterization
        let width = Int(mediaBox.width * scale)
        let height = Int(mediaBox.height * scale)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw FloorPlanImportError.pdfRenderFailed
        }

        // Fill white background
        context.setFillColor(CGColor.white)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        // Scale and draw PDF page
        context.scaleBy(x: scale, y: scale)
        context.drawPDFPage(page)

        guard let cgImage = context.makeImage()
        else {
            throw FloorPlanImportError.pdfRenderFailed
        }

        return encodePNG(cgImage)
    }

    /// Creates a CGImage from raw image data (PNG, JPEG, HEIC).
    private static func createCGImage(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            return nil
        }
        return cgImage
    }

    /// Downsamples a CGImage if it exceeds `maxPixelDimension` in either axis.
    private static func downsampleIfNeeded(_ image: CGImage) -> CGImage {
        let maxDim = max(image.width, image.height)
        guard maxDim > maxPixelDimension
        else {
            return image
        }

        let scaleFactor = Double(maxPixelDimension) / Double(maxDim)
        let newWidth = Int(Double(image.width) * scaleFactor)
        let newHeight = Int(Double(image.height) * scaleFactor)

        let colorSpace = image.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: newWidth,
            height: newHeight,
            bitsPerComponent: 8,
            bytesPerRow: newWidth * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return image
        }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))

        return context.makeImage() ?? image
    }

    /// Encodes a CGImage as PNG data.
    private static func encodePNG(_ image: CGImage) -> Data {
        let rep = NSBitmapImageRep(cgImage: image)
        return rep.representation(using: .png, properties: [:]) ?? Data()
    }
}
