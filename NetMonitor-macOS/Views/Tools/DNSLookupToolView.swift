//
//  DNSLookupToolView.swift
//  NetMonitor
//
//  DNS lookup tool using /usr/bin/dig.
//

import SwiftUI
import NetMonitorCore

struct DNSLookupToolView: View {
    @Environment(\.appAccentColor) private var accentColor
    @State private var hostname = ""
    @State private var recordType: DNSRecordType = .a
    @State private var isRunning = false
    @State private var results: [String] = []
    @State private var errorMessage: String?
    @State private var lookupTask: Task<Void, Never>?
    @AppStorage("netmonitor.lastUsedTarget") private var lastUsedTarget: String = ""

    private let runner = ShellCommandRunner()

    var body: some View {
        ToolSheetContainer(
            title: "DNS Lookup",
            iconName: "magnifyingglass",
            closeAccessibilityID: "dns_button_close",
            inputArea: { inputArea },
            outputArea: { outputArea },
            footerContent: { footer }
        )
        .onAppear {
            if hostname.isEmpty && !lastUsedTarget.isEmpty {
                hostname = lastUsedTarget
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
            TextField("Hostname (e.g., example.com)", text: $hostname)
                .textFieldStyle(.roundedBorder)
                .onSubmit { runLookup() }
                .disabled(isRunning)
                .accessibilityIdentifier("dns_textfield_hostname")

            Picker("Type", selection: $recordType) {
                ForEach(DNSRecordType.allCases, id: \.self) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .frame(width: 100)
            .disabled(isRunning)
            .accessibilityIdentifier("dns_picker_type")

            Button("Lookup") {
                runLookup()
            }
            .buttonStyle(.borderedProminent)
            .disabled(hostname.isEmpty || isRunning)
            .accessibilityIdentifier("dns_button_lookup")
        }
        .padding()
    }

    // MARK: - Output Area

    private var outputArea: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                if results.isEmpty && errorMessage == nil && !isRunning {
                    Text("Enter a hostname and select a record type to query")
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 40)
                } else {
                    ForEach(Array(results.enumerated()), id: \.offset) { _, result in
                        resultRow(result)
                    }

                    if let error = errorMessage {
                        Text(error)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.red)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .background(Color.black.opacity(0.2))
    }

    private func resultRow(_ result: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: iconForResult(result))
                .foregroundStyle(accentColor)
                .frame(width: 20)

            Text(result)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
        }
        .padding(.vertical, 2)
    }

    private func iconForResult(_ _: String) -> String {
        switch recordType {
        case .a, .aaaa:
            return "network"
        case .mx:
            return "envelope"
        case .txt:
            return "text.quote"
        case .cname:
            return "arrow.triangle.branch"
        case .ns:
            return "server.rack"
        case .soa:
            return "doc.text"
        case .ptr:
            return "arrow.uturn.backward"
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if isRunning {
                ProgressView()
                    .scaleEffect(0.7)
                Text("Querying DNS...")
                    .foregroundStyle(.secondary)
            } else if !results.isEmpty {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("\(results.count) record(s) found")
                    .foregroundStyle(.secondary)
            } else if errorMessage != nil {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Query failed")
                    .foregroundStyle(.secondary)
            } else {
                Text("Query DNS records for any hostname")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !results.isEmpty && !isRunning {
                Button("Clear") {
                    results.removeAll()
                    errorMessage = nil
                }
                .accessibilityIdentifier("dns_button_clear")
            }
        }
        .padding()
    }

    // MARK: - Actions

    private func runLookup() {
        guard !hostname.isEmpty else { return }

        lastUsedTarget = hostname
        isRunning = true
        results.removeAll()
        errorMessage = nil

        lookupTask = Task {
            do {
                let output = try await runner.run(
                    "/usr/bin/dig",
                    arguments: ["+short", recordType.rawValue, hostname],
                    timeout: 10
                )

                await MainActor.run {
                    let lines = output.stdout
                        .components(separatedBy: .newlines)
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }

                    if lines.isEmpty {
                        errorMessage = "No \(recordType.rawValue) records found for \(hostname)"
                    } else {
                        results = lines
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
    DNSLookupToolView()
}
