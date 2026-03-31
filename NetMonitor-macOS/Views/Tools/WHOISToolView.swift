//
//  WHOISToolView.swift
//  NetMonitor
//
//  WHOIS lookup tool using the shared WHOISService from NetMonitorCore.
//

import SwiftUI
import NetMonitorCore

struct WHOISToolView: View {
    @Environment(\.appAccentColor) private var accentColor
    @State private var domain = ""
    @State private var isRunning = false
    @State private var errorMessage: String?
    @State private var result: WHOISResult?
    @State private var showRawOutput = false
    @State private var lookupTask: Task<Void, Never>?
    @AppStorage("netmonitor.lastUsedTarget") private var lastUsedTarget: String = ""

    private let service = WHOISService()

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        ToolSheetContainer(
            title: "WHOIS",
            iconName: "doc.text.magnifyingglass",
            closeAccessibilityID: "whois_button_close",
            inputArea: { inputArea },
            outputArea: { outputArea },
            footerContent: { footer }
        )
        .onAppear {
            if domain.isEmpty && !lastUsedTarget.isEmpty {
                domain = lastUsedTarget
            }
        }
        .onDisappear {
            lookupTask?.cancel()
            lookupTask = nil
        }
    }

    // MARK: - Input Area

    private var inputArea: some View {
        HStack(spacing: 12) {
            TextField("Domain name (e.g., example.com)", text: $domain)
                .textFieldStyle(.roundedBorder)
                .onSubmit { runWhois() }
                .disabled(isRunning)
                .accessibilityIdentifier("whois_textfield_domain")

            Button("Lookup") {
                runWhois()
            }
            .buttonStyle(.borderedProminent)
            .disabled(domain.isEmpty || isRunning)
            .accessibilityIdentifier("whois_button_lookup")
        }
        .padding()
    }

    // MARK: - Output Area

    private var outputArea: some View {
        VStack(spacing: 0) {
            // Toggle for parsed vs raw view
            if result != nil {
                HStack {
                    Picker("View Mode", selection: $showRawOutput) {
                        Text("Parsed").tag(false)
                        Text("Raw").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                    .accessibilityIdentifier("whois_picker_viewmode")

                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(MacTheme.Colors.subtleBackgroundLight)
            }

            // Content area
            if result == nil && errorMessage == nil && !isRunning {
                ScrollView {
                    Text("Enter a domain name to lookup registration information")
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 40)
                }
                .background(MacTheme.Colors.subtleBackground)
            } else if let error = errorMessage {
                ScrollView {
                    Text(error)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .background(MacTheme.Colors.subtleBackground)
            } else if showRawOutput || result == nil {
                rawView
            } else {
                parsedView
            }
        }
    }

    private var rawView: some View {
        ScrollView {
            Text(result?.rawData ?? "")
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .background(MacTheme.Colors.subtleBackground)
    }

    private var parsedView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Domain section
                sectionView(title: "Domain", icon: "globe") {
                    infoRow("Domain Name", result?.query ?? "")
                    if let registrar = result?.registrar {
                        infoRow("Registrar", registrar)
                    }
                }

                // Dates section
                if result?.creationDate != nil || result?.expirationDate != nil {
                    sectionView(title: "Dates", icon: "calendar") {
                        if let created = result?.creationDate {
                            infoRow("Created", Self.dateFormatter.string(from: created))
                        }
                        if let expires = result?.expirationDate {
                            infoRow("Expires", Self.dateFormatter.string(from: expires))
                        }
                        if let updated = result?.updatedDate {
                            infoRow("Updated", Self.dateFormatter.string(from: updated))
                        }
                    }
                }

                // Name Servers section
                if let nameServers = result?.nameServers, !nameServers.isEmpty {
                    sectionView(title: "Name Servers", icon: "server.rack") {
                        ForEach(nameServers, id: \.self) { ns in
                            Text(ns).font(.system(.body, design: .monospaced))
                        }
                    }
                }

                // Status section
                if let statuses = result?.status, !statuses.isEmpty {
                    sectionView(title: "Status", icon: "checkmark.shield") {
                        ForEach(statuses, id: \.self) { status in
                            Text(status).font(.system(.body, design: .monospaced))
                        }
                    }
                }
            }
            .padding()
        }
        .background(MacTheme.Colors.subtleBackground)
        .accessibilityIdentifier("whois_section_parsed")
    }

    private func sectionView(title: String, icon: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(accentColor)

            VStack(alignment: .leading, spacing: 4) {
                content()
            }
            .padding(.leading, 4)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .macGlassCard(cornerRadius: 8, padding: 0)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .leading)
            Text(value)
                .textSelection(.enabled)
                .font(.system(.body, design: .monospaced))
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if isRunning {
                ProgressView()
                    .scaleEffect(0.7)
                Text("Looking up \(domain)...")
                    .foregroundStyle(.secondary)
            } else if result != nil {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("WHOIS data retrieved")
                    .foregroundStyle(.secondary)
            } else if errorMessage != nil {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Lookup failed")
                    .foregroundStyle(.secondary)
            } else {
                Text("Query domain registration information")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if result != nil && !isRunning {
                Button("Clear") {
                    result = nil
                    errorMessage = nil
                }
                .accessibilityIdentifier("whois_button_clear")
            }
        }
        .padding()
    }

    // MARK: - Actions

    private func runWhois() {
        guard !domain.isEmpty else { return }

        lastUsedTarget = domain
        isRunning = true
        errorMessage = nil
        result = nil
        showRawOutput = false

        lookupTask = Task {
            do {
                let whoisResult = try await service.lookup(query: domain)
                await MainActor.run {
                    if whoisResult.rawData.isEmpty {
                        errorMessage = "No WHOIS data found for \(domain)"
                    } else {
                        result = whoisResult
                    }
                    isRunning = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isRunning = false
                }
            }
        }
    }
}

#Preview {
    WHOISToolView()
}
