//
//  ConnectivityCardViewModel.swift
//  NetMonitor
//

import Foundation
import Observation

@MainActor
@Observable
final class ConnectivityCardViewModel {
    private(set) var ispInfo: ISPLookupService.ISPInfo?
    var loadError: String?

    private let service: any ISPLookupServiceProtocol

    init(service: any ISPLookupServiceProtocol = ISPLookupService()) {
        self.service = service
    }

    func load() async {
        do {
            ispInfo = try await service.lookup()
        } catch {
            loadError = error.localizedDescription
        }
    }
}
