//
//  WHOISToolView.swift
//  NetMonitor
//
//  WHOIS lookup tool using /usr/bin/whois.
//

import SwiftUI

struct WHOISInfo {
    var domainName: String?
    var registrar: String?
    var creationDate: String?
    var expirationDate: String?
    var updatedDate: String?
    var nameServers: [String] = []
    var status: [String] = []
    var registrantOrg: String?
    var registrantCountry: String?
    var dnssec: String?
    var rawText: String

    static func parse(from rawText: String) -> WHOISInfo {
        var info = WHOISInfo(rawText: rawText)
        let lines = rawText.components(separatedBy: "\n")

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.contains(":") else { continue }

            let parts = trimmed.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }

            let key = String(parts[0]).trimmingCharacters(in: .whitespaces).lowercased()
            let value = String(parts[1]).trimmingCharacters(in: .whitespaces)

            guard !value.isEmpty else { continue }

            switch key {
            case "domain name":
                info.domainName = value
            case "registrar", "registrar name":
                info.registrar = value
            case "creation date", "created", "created date":
                info.creationDate = value
            case "registry expiry date", "expiration date", "expires", "expiry date":
                info.expirationDate = value
            case "updated date", "last updated":
                info.updatedDate = value
            case "name server":
                info.nameServers.append(value.lowercased())
            case "domain status":
                let statusName = value.components(separatedBy: " ").first ?? value
                info.status.append(statusName)
            case "registrant organization":
                info.registrantOrg = value
            case "registrant country":
                info.registrantCountry = value
            case "dnssec":
                info.dnssec = value
            default:
                break
            }
        }

        return info
    }
}

struct WHOISToolView: View {
    @Environment(\.appAccentColor) private var accentColor
    @State private var domain = ""
    @State private var isRunning = false
    @State private var output = ""
    @State private var errorMessage: String?
    @State private var parsedInfo: WHOISInfo?
    @State private var showRawOutput = false
    @State private var lookupTask: Task<Void, Never>?

    private let runner = ShellCommandRunner()

    var body: some View {
        ToolSheetContainer(
            title: "WHOIS",
            iconName: "doc.text.magnifyingglass",
            closeAccessibilityID: "whois_button_close",
            inputArea: { inputArea },
            outputArea: { outputArea },
            footerContent: { footer }
        )
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
            if parsedInfo != nil {
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
                .background(Color.black.opacity(0.1))
            }

            // Content area
            if output.isEmpty && errorMessage == nil && !isRunning {
                ScrollView {
                    Text("Enter a domain name to lookup registration information")
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 40)
                }
                .background(Color.black.opacity(0.2))
            } else if let error = errorMessage {
                ScrollView {
                    Text(error)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .background(Color.black.opacity(0.2))
            } else if showRawOutput || parsedInfo == nil {
                rawView
            } else {
                parsedView
            }
        }
    }

    private var rawView: some View {
        ScrollView {
            Text(output)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .background(Color.black.opacity(0.2))
    }

    private var parsedView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Domain section
                if let domain = parsedInfo?.domainName {
                    sectionView(title: "Domain", icon: "globe") {
                        infoRow("Domain Name", domain)
                        if let registrar = parsedInfo?.registrar {
                            infoRow("Registrar", registrar)
                        }
                        if let org = parsedInfo?.registrantOrg {
                            infoRow("Organization", org)
                        }
                        if let country = parsedInfo?.registrantCountry {
                            infoRow("Country", country)
                        }
                    }
                }

                // Dates section
                if parsedInfo?.creationDate != nil || parsedInfo?.expirationDate != nil {
                    sectionView(title: "Dates", icon: "calendar") {
                        if let created = parsedInfo?.creationDate {
                            infoRow("Created", created)
                        }
                        if let expires = parsedInfo?.expirationDate {
                            infoRow("Expires", expires)
                        }
                        if let updated = parsedInfo?.updatedDate {
                            infoRow("Updated", updated)
                        }
                    }
                }

                // Name Servers section
                if let nameServers = parsedInfo?.nameServers, !nameServers.isEmpty {
                    sectionView(title: "Name Servers", icon: "server.rack") {
                        ForEach(nameServers, id: \.self) { ns in
                            Text(ns).font(.system(.body, design: .monospaced))
                        }
                    }
                }

                // Status section
                if let statuses = parsedInfo?.status, !statuses.isEmpty {
                    sectionView(title: "Status", icon: "checkmark.shield") {
                        ForEach(statuses, id: \.self) { status in
                            Text(status).font(.system(.body, design: .monospaced))
                        }
                    }
                }

                // DNSSEC section
                if let dnssec = parsedInfo?.dnssec {
                    sectionView(title: "Security", icon: "lock.shield") {
                        infoRow("DNSSEC", dnssec)
                    }
                }
            }
            .padding()
        }
        .background(Color.black.opacity(0.2))
    }

    private func sectionView<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
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
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
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
            } else if !output.isEmpty {
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

            if !output.isEmpty && !isRunning {
                Button("Clear") {
                    output = ""
                    errorMessage = nil
                    parsedInfo = nil
                }
                .accessibilityIdentifier("whois_button_clear")
            }
        }
        .padding()
    }

    // MARK: - Actions

    private func runWhois() {
        guard !domain.isEmpty else { return }

        isRunning = true
        output = ""
        errorMessage = nil
        parsedInfo = nil
        showRawOutput = false

        lookupTask = Task {
            do {
                let result = try await runner.run(
                    "/usr/bin/whois",
                    arguments: [domain],
                    timeout: 30
                )

                await MainActor.run {
                    if result.stdout.isEmpty {
                        errorMessage = "No WHOIS data found for \(domain)"
                    } else {
                        output = result.stdout
                        parsedInfo = WHOISInfo.parse(from: result.stdout)
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
