import Foundation
import NetMonitorCore

/// ViewModel for the WHOIS tool view
@MainActor
@Observable
final class WHOISToolViewModel {
    // MARK: - Input Properties

    var domain: String = "" {
        didSet {
            let trimmed = domain.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                TargetManager.shared.currentTarget = trimmed
            }
        }
    }

    // MARK: - State Properties

    var isLoading: Bool = false
    var result: WHOISResult?
    var errorMessage: String?

    // MARK: - Dependencies

    private let whoisService: any WHOISServiceProtocol
    private let activityLog: ToolActivityLog

    init(
        whoisService: any WHOISServiceProtocol = WHOISService(),
        initialDomain: String? = nil,
        activityLog: ToolActivityLog = .shared
    ) {
        self.whoisService = whoisService
        self.activityLog = activityLog
        if let initialDomain = initialDomain {
            self.domain = initialDomain
        }
    }

    // MARK: - Computed Properties

    var canStartLookup: Bool {
        !domain.trimmingCharacters(in: .whitespaces).isEmpty && !isLoading
    }

    // MARK: - Actions

    func lookup() async {
        guard canStartLookup else { return }

        let trimmed = domain.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            TargetManager.shared.setTarget(trimmed)
        }

        isLoading = true
        errorMessage = nil

        let trimmedDomain = domain.trimmingCharacters(in: .whitespaces)
        do {
            result = try await whoisService.lookup(query: trimmedDomain)
            activityLog.add(
                tool: "WHOIS",
                target: trimmedDomain,
                result: "Lookup complete",
                success: true
            )
        } catch {
            errorMessage = NetworkError.from(error).userFacingMessage
            activityLog.add(
                tool: "WHOIS",
                target: trimmedDomain,
                result: "Failed",
                success: false
            )
        }

        isLoading = false
    }

    func clearResults() {
        result = nil
        errorMessage = nil
    }
}
