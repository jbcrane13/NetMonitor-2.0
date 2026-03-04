import CoreGraphics
import Foundation
import ImageIO
import os
import UniformTypeIdentifiers

// MARK: - FloorPlanImportError

/// Errors that can occur during floor plan import on iOS.
enum FloorPlanImportError: LocalizedError, Sendable {
    case unsupportedFormat(String)
    case fileReadFailed(String)
    case imageDecodeFailed
    case pdfRenderFailed
    case cancelled

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
        case .cancelled:
            "Import was cancelled"
        }
    }
}

// MARK: - FloorPlanImportResult

/// The result of importing a floor plan image.
struct FloorPlanImportResult: Sendable {
    let imageData: Data
    let pixelWidth: Int
    let pixelHeight: Int
    let sourceURL: URL?
}

// MARK: - FloorPlanImporter

/// Utility for importing floor plan images on iOS from various formats.
/// Supports PNG, JPEG, HEIC (via PHPicker) and PNG, JPEG, PDF (via UIDocumentPicker).
/// Large images are downsampled to keep memory usage reasonable.
enum FloorPlanImporter {

    // MARK: - Constants

    /// Maximum pixel dimension (width or height) for imported images.
    static let maxPixelDimension: Int = 4096

    /// File extensions accepted from document picker.
    static let supportedDocumentExtensions: Set<String> = ["png", "jpg", "jpeg", "pdf"]

    /// UTTypes for UIDocumentPickerViewController.
    static let documentPickerTypes: [UTType] = [
        .png,
        .jpeg,
        .pdf
    ]

    // MARK: - Import from Data

    /// Imports a floor plan from raw image data (e.g., from PHPickerViewController).
    /// - Parameter data: Raw image data (PNG, JPEG, HEIC).
    /// - Returns: A `FloorPlanImportResult` with PNG image data and dimensions.
    static func importFloorPlan(from data: Data) throws -> FloorPlanImportResult {
        guard let cgImage = createCGImage(from: data) else {
            throw FloorPlanImportError.imageDecodeFailed
        }

        let downsampled = downsampleIfNeeded(cgImage)
        let pngData = encodePNG(downsampled)

        Logger.heatmap.debug("Floor plan imported from data: \(downsampled.width)x\(downsampled.height)")

        return FloorPlanImportResult(
            imageData: pngData,
            pixelWidth: downsampled.width,
            pixelHeight: downsampled.height,
            sourceURL: nil
        )
    }

    // MARK: - Import from URL

    /// Imports a floor plan from a file URL (e.g., from UIDocumentPickerViewController).
    /// Handles format detection, PDF rasterization, large-image downsampling, and PNG encoding.
    /// - Parameter url: File URL to the floor plan image.
    /// - Returns: A `FloorPlanImportResult` with PNG image data and dimensions.
    static func importFloorPlan(from url: URL) throws -> FloorPlanImportResult {
        let ext = url.pathExtension.lowercased()

        guard supportedDocumentExtensions.contains(ext) else {
            throw FloorPlanImportError.unsupportedFormat(ext)
        }

        let imageData: Data
        if ext == "pdf" {
            imageData = try rasterizePDF(at: url)
        } else {
            guard let data = try? Data(contentsOf: url) else {
                throw FloorPlanImportError.fileReadFailed(url.path)
            }
            imageData = data
        }

        guard let cgImage = createCGImage(from: imageData) else {
            throw FloorPlanImportError.imageDecodeFailed
        }

        let downsampled = downsampleIfNeeded(cgImage)
        let pngData = encodePNG(downsampled)

        Logger.heatmap.debug("Floor plan imported from file: \(downsampled.width)x\(downsampled.height) (\(ext))")

        return FloorPlanImportResult(
            imageData: pngData,
            pixelWidth: downsampled.width,
            pixelHeight: downsampled.height,
            sourceURL: url
        )
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
        let scale: CGFloat = 2.0
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
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        // Scale and draw PDF page
        context.scaleBy(x: scale, y: scale)
        context.drawPDFPage(page)

        guard let cgImage = context.makeImage() else {
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
        guard maxDim > maxPixelDimension else {
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
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, UTType.png.identifier as CFString, 1, nil) else {
            return Data()
        }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        return data as Data
    }
}
