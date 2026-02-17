//
//  ISPInfoCard.swift
//  NetMonitor
//
//  Created by Claude on 2026-01-28.
//

import SwiftUI

struct ISPInfoCard: View {

    // MARK: - Properties

    @Environment(\.appAccentColor) private var accentColor
    @State private var ispInfo: ISPLookupService.ISPInfo?
    @State private var isLoading = true
    @State private var errorMessage: String?

    private let ispLookupService: ISPLookupService

    // MARK: - Initialization

    init(ispLookupService: ISPLookupService = ISPLookupService()) {
        self.ispLookupService = ispLookupService
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with refresh button
            HStack {
                Label("Public IP & ISP", systemImage: "network")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer()

                Button {
                    Task { await loadISPInfo() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .imageScale(.medium)
                        .foregroundStyle(accentColor)
                }
                .buttonStyle(.plain)
                .disabled(isLoading)
                .accessibilityIdentifier("isp_card_button_refresh")
            }

            Divider()

            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                        .controlSize(.small)
                    Spacer()
                }
            } else if let info = ispInfo {
                // Public IP
                HStack {
                    Text("Public IP:")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(info.publicIP)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.primary)
                }

                // ISP
                HStack {
                    Label("ISP:", systemImage: "network")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(info.isp)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                // ASN (if available)
                if let asn = info.asn {
                    HStack {
                        Text("ASN:")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(asn)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(accentColor)
                    }
                }

                // Location
                if let city = info.city, let country = info.country {
                    HStack {
                        Label("Location:", systemImage: "globe.americas")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(city), \(country)")
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                } else if let country = info.country {
                    HStack {
                        Label("Location:", systemImage: "globe.americas")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(country)
                            .foregroundStyle(.primary)
                    }
                }
            } else if let error = errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.yellow)
                    Text(error)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            } else {
                Text("Unable to determine")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .task {
            await loadISPInfo()
        }
    }

    // MARK: - Methods

    private func loadISPInfo() async {
        isLoading = true
        errorMessage = nil

        do {
            let info = try await ispLookupService.lookup()
            withAnimation {
                self.ispInfo = info
                self.isLoading = false
            }
        } catch {
            withAnimation {
                self.errorMessage = handleError(error)
                self.isLoading = false
            }
        }
    }

    private func handleError(_ error: Error) -> String {
        if let ispError = error as? ISPLookupError {
            return ispError.localizedDescription
        } else if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet:
                return "No internet connection"
            case .timedOut:
                return "Request timed out"
            default:
                return "Unable to determine"
            }
        } else {
            return "Unable to determine"
        }
    }
}

// MARK: - Preview

#Preview {
    ISPInfoCard()
        .frame(width: 300)
        .padding()
}
