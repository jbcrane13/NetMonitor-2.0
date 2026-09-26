import Foundation
import XCTest

/// Guards against regressions of issue #320: dashboard cards, the Home Screen
/// widget, and the Network Map page must not use fixed point sizes below
/// 11pt, since those ignore Dynamic Type and are hard to read.
///
/// This scans the raw source of the three affected files for
/// `.system(size: N, ...)` font modifiers and fails if any use a point size
/// below 11. It intentionally does not flag `Font.system(.caption2, ...)`
/// and other semantic-text-style usages, since those scale with Dynamic Type.
final class ReadableFontSizeTests: XCTestCase {
    private static let minimumAllowedPointSize: Double = 11

    private static let filesToCheck = [
        "NetMonitor-iOS/Views/Dashboard/DashboardView.swift",
        "NetMonitor-iOS/Widget/NetmonitorWidget.swift",
        "NetMonitor-iOS/Views/NetworkMap/NetworkMapView.swift"
    ]

    func testNoFixedFontSizesBelowMinimumOnAffectedSurfaces() throws {
        let repositoryRootURL = try Self.findRepositoryRoot(startingAt: URL(fileURLWithPath: #filePath))
        let pattern = try NSRegularExpression(pattern: #"\.system\(\s*size:\s*(\d+(?:\.\d+)?)"#)

        for relativePath in Self.filesToCheck {
            let fileURL = repositoryRootURL.appendingPathComponent(relativePath)
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            let fullRange = NSRange(source.startIndex..<source.endIndex, in: source)

            let matches = pattern.matches(in: source, range: fullRange)
            for match in matches {
                guard let sizeRange = Range(match.range(at: 1), in: source) else { continue }
                let sizeText = String(source[sizeRange])
                let size = try XCTUnwrap(Double(sizeText), "Could not parse font size '\(sizeText)' in \(relativePath)")
                XCTAssertGreaterThanOrEqual(
                    size,
                    Self.minimumAllowedPointSize,
                    "\(relativePath) uses a fixed font size of \(sizeText)pt, below the \(Int(Self.minimumAllowedPointSize))pt " +
                        "readability floor. Use a semantic text style (e.g. Font.system(.caption2, weight:, design:)) or " +
                        "@ScaledMetric instead so the text follows Dynamic Type."
                )
            }
        }
    }

    private static func findRepositoryRoot(startingAt url: URL) throws -> URL {
        var current = url.deletingLastPathComponent()

        while current.path != "/" {
            if FileManager.default.fileExists(atPath: current.appendingPathComponent("project.yml").path) {
                return current
            }
            current.deleteLastPathComponent()
        }

        throw XCTSkip("Unable to locate repository root from \(url.path)")
    }
}
