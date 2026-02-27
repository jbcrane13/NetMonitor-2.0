//
//  ISPCardViewModel.swift
//  NetMonitor
//

import Foundation
import Observation

@MainActor
@Observable
final class ISPCardViewModel {
    private(set) var ispInfo: ISPLookupService.ISPInfo?
    private(set) var isLoading = true
    var errorMessage: String?

    private let service: any ISPLookupServiceProtocol

    init(service: any ISPLookupServiceProtocol = ISPLookupService()) {
        self.service = service
    }

    func load() async {
        do {
            ispInfo = try await service.lookup()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
