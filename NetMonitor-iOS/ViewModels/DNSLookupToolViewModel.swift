import Foundation
import NetMonitorCore

/// ViewModel for the DNS Lookup tool view
@MainActor
@Observable
final class DNSLookupToolViewModel {
    // MARK: - Input Properties

    var domain: String = "" {
        didSet {
            let trimmed = domain.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                TargetManager.shared.currentTarget = trimmed
            }
        }
    }

    var recordType: DNSRecordType = .a

    // MARK: - State Properties

    var isLoading: Bool = false
    var result: DNSQueryResult?
    var errorMessage: String?

    // MARK: - Dependencies

    private let dnsService: any DNSLookupServiceProtocol

    init(dnsService: any DNSLookupServiceProtocol = DNSLookupService(), initialDomain: String? = nil) {
        self.dnsService = dnsService
        if let initialDomain = initialDomain {
            self.domain = initialDomain
        }
    }

    // MARK: - Computed Properties

    var canStartLookup: Bool {
        !domain.trimmingCharacters(in: .whitespaces).isEmpty && !isLoading
    }

    var recordTypes: [DNSRecordType] {
        [.a, .aaaa, .mx, .txt, .cname, .ns, .soa, .ptr]
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

        let customServer = UserDefaults.standard.string(forKey: AppSettings.Keys.dnsServer)
        let effectiveServer = (customServer?.isEmpty ?? true) ? nil : customServer
        result = await dnsService.lookup(
            domain: domain.trimmingCharacters(in: .whitespaces),
            recordType: recordType,
            server: effectiveServer
        )

        let trimmedDomain = domain.trimmingCharacters(in: .whitespaces)
        if let result {
            ToolActivityLog.shared.add(
                tool: "DNS Lookup",
                target: trimmedDomain,
                result: "\(result.records.count) records",
                success: true
            )
        } else {
            errorMessage = dnsService.lastError ?? "Lookup failed"
            ToolActivityLog.shared.add(
                tool: "DNS Lookup",
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
