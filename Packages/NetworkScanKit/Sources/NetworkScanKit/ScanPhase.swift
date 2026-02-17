import Foundation

/// A composable phase of a network scan.
///
/// Each phase implements a single discovery technique (ARP, Bonjour, TCP probe, etc.).
/// Phases are orchestrated by ``ScanEngine`` according to a ``ScanPipeline``.
public protocol ScanPhase: Sendable {
    /// Unique identifier for this phase.
    var id: String { get }

    /// Human-readable name shown during scanning.
    var displayName: String { get }

    /// Relative weight for progress calculation across the pipeline.
    var weight: Double { get }

    /// Execute the scan phase.
    ///
    /// - Parameters:
    ///   - context: Shared scan context (hosts, subnet filter, local IP).
    ///   - accumulator: Thread-safe accumulator for discovered devices.
    ///   - onProgress: Callback reporting phase-local progress (0.0–1.0).
    func execute(
        context: ScanContext,
        accumulator: ScanAccumulator,
        onProgress: @Sendable (Double) async -> Void
    ) async
}
