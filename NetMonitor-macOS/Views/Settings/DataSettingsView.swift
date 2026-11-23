//
//  DataSettingsView.swift
//  NetMonitor
//
//  Data management and export settings.
//

import SwiftUI
import NetMonitorCore
import SwiftData
import UniformTypeIdentifiers
import os

struct DataSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(DeviceDiscoveryCoordinator.self) private var deviceDiscovery: DeviceDiscoveryCoordinator?
    @AppStorage(HistoryRetention.key) private var historyRetention = HistoryRetention.default.rawValue

    @State private var showExportDialog = false
    @State private var showClearConfirmation = false
    @State private var exportURL: URL?

    var body: some View {
        Form {
            SwiftUI.Section {
                Picker("Keep measurement history", selection: $historyRetention) {
                    ForEach(HistoryRetention.allCases, id: \.self) { retention in
                        Text(retention.rawValue).tag(retention.rawValue)
                    }
                }
                .accessibilityIdentifier("settings_picker_historyRetention")
            } header: {
                Text("History")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Older measurements, monitoring sessions and timeline events will be automatically deleted to save space.")
                    Text("Event history keeps up to the newest 20,000 events.")
                        .accessibilityIdentifier("settings_label_eventHistoryCeiling")
                }
            }

            SwiftUI.Section {
                Button("Export Data to CSV...") {
                    exportData()
                }
                .accessibilityIdentifier("settings_button_export")

                Button("Clear All Data...", role: .destructive) {
                    showClearConfirmation = true
                }
                .accessibilityIdentifier("settings_button_clearData")
            } header: {
                Text("Management")
            }
        }
        .formStyle(.grouped)
        .padding()
        .navigationTitle("Data")
        .fileExporter(
            isPresented: $showExportDialog,
            document: CSVDocument(url: exportURL),
            contentType: .commaSeparatedText,
            defaultFilename: "netmonitor-export"
        ) { _ in
            // Handle export result
        }
        .alert("Clear All Data?", isPresented: $showClearConfirmation) {
            Button("Cancel", role: .cancel) {}
                .accessibilityIdentifier("settings_button_cancelClearData")
            Button("Clear", role: .destructive) {
                clearAllData()
            }
            .accessibilityIdentifier("settings_button_confirmClearData")
        } message: {
            Text("This will delete all targets, measurements, and discovered devices. This action cannot be undone.")
        }
    }

    private func exportData() {
        // Create a temporary file with exported data
        let tempDir = FileManager.default.temporaryDirectory
        let exportFile = tempDir.appendingPathComponent("netmonitor-export.csv")

        var csvContent = "Type,Name,Value,Timestamp\n"

        // Export would include targets and measurements
        // For now, just create a sample export
        csvContent += "info,export_date,\(Date().ISO8601Format()),\(Date().ISO8601Format())\n"

        do {
            try csvContent.write(to: exportFile, atomically: true, encoding: .utf8)
            exportURL = exportFile
            showExportDialog = true
        } catch {
            Logger.data.error("Export failed: \(error, privacy: .public)")
        }
    }

    private func clearAllData() {
        // A suggestion pass must not write to the rows deleted below (#449).
        deviceDiscovery?.cancelSuggestions()
        do {
            try modelContext.delete(model: TargetMeasurement.self)
            try modelContext.delete(model: NetworkTarget.self)
            try modelContext.delete(model: LocalDevice.self)
            try modelContext.delete(model: SessionRecord.self)
            try modelContext.save()
            // Forget remembered devices too, so change detection starts a fresh baseline (#393).
            DeviceChangeTracker().clearAll()
            DeviceSuggestionStore().clearAll()
        } catch {
            Logger.data.error("Failed to clear data: \(error, privacy: .public)")
        }
    }
}

// MARK: - CSV Document for Export

struct CSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }

    var url: URL?

    init(url: URL?) {
        self.url = url
    }

    init(configuration: ReadConfiguration) throws {
        self.url = nil
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        guard let url = url,
              let data = try? Data(contentsOf: url) else {
            return FileWrapper(regularFileWithContents: Data())
        }
        return FileWrapper(regularFileWithContents: data)
    }
}

#Preview {
    DataSettingsView()
}
