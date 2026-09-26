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

    /// When true, `lookup()` queries every supported record type and merges the
    /// results instead of just `recordType`.
    var queryAllTypes: Bool = false

    // MARK: - State Properties

    var isLoading: Bool = false
    var result: DNSQueryResult?
    var errorMessage: String?

    // MARK: - Dependencies

    private let dnsService: any DNSLookupServiceProtocol
    private let activityLog: ToolActivityLog

    init(
        dnsService: any DNSLookupServiceProtocol = DNSLookupService(),
        initialDomain: String? = nil,
        activityLog: ToolActivityLog = .shared
    ) {
        self.dnsService = dnsService
        self.activityLog = activityLog
        if let initialDomain = initialDomain {
            self.domain = initialDomain
        }
    }

    // MARK: - Computed Properties

    var canStartLookup: Bool {
        !domain.trimmingCharacters(in: .whitespaces).isEmpty && !isLoading
    }

    var recordTypes: [DNSRecordType] {
        [.a, .aaaa, .mx, .txt, .cname, .ns, .soa, .ptr, .caa, .srv, .https]
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
        let trimmedInput = domain.trimmingCharacters(in: .whitespaces)
        if queryAllTypes {
            result = await dnsService.lookupAll(domain: trimmedInput, server: effectiveServer)
        } else {
            result = await dnsService.lookup(
                domain: trimmedInput,
                recordType: recordType,
                server: effectiveServer
            )
        }

        let trimmedDomain = domain.trimmingCharacters(in: .whitespaces)
        if let result {
            activityLog.add(
                tool: "DNS Lookup",
                target: trimmedDomain,
                result: "\(result.records.count) records",
                success: true
            )
        } else {
            errorMessage = dnsService.lastError ?? "Lookup failed"
            activityLog.add(
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
