import Testing
import Foundation
@testable import NetMonitor_macOS
import NetMonitorCore

// MARK: - Mock Service

private final class StubHeatmapService: WiFiHeatmapServiceProtocol, @unchecked Sendable {
    private var _data: [HeatmapDataPoint] = []

    func startSurvey() { _data = [] }
    func stopSurvey() {}

    func recordDataPoint(signalStrength: Int, x: Double, y: Double) {
        _data.append(HeatmapDataPoint(x: x, y: y, signalStrength: signalStrength))
    }

    func getSurveyData() -> [HeatmapDataPoint] { _data }
}

// MARK: - Tests

@Suite("Dashboard Error Surfacing")
@MainActor
struct DashboardErrorSurfacingTests {

    /// The UserDefaults key used by WiFiHeatmapToolViewModel for persistence.
    private static let surveysKey = "wifiHeatmap_surveys_mac"

    // MARK: - WiFiHeatmapToolViewModel persistence error tests

    @Test func persistenceErrorIsNilInitially() {
        // Clean slate: remove any existing data for the key
        UserDefaults.standard.removeObject(forKey: Self.surveysKey)
        let vm = WiFiHeatmapToolViewModel(service: StubHeatmapService())
        #expect(vm.persistenceError == nil)
    }

    @Test func loadSurveysWithCorruptDataSetsPersistenceError() {
        // Write corrupt (non-decodable) data to UserDefaults
        let corruptData = Data("this is not valid JSON".utf8)
        UserDefaults.standard.set(corruptData, forKey: Self.surveysKey)

        let vm = WiFiHeatmapToolViewModel(service: StubHeatmapService())

        #expect(vm.persistenceError != nil)
        #expect(vm.surveys.isEmpty)

        // Clean up
        UserDefaults.standard.removeObject(forKey: Self.surveysKey)
    }

    @Test func saveSurveysWithValidDataLeavesPersistenceErrorNil() {
        // Start with clean state
        UserDefaults.standard.removeObject(forKey: Self.surveysKey)

        let service = StubHeatmapService()
        let vm = WiFiHeatmapToolViewModel(service: service)

        // Record data and stop survey to trigger saveSurveys()
        vm.startSurvey()
        vm.recordDataPoint(at: CGPoint(x: 50, y: 50), in: CGSize(width: 100, height: 100))
        vm.stopSurvey()

        #expect(vm.persistenceError == nil)
        #expect(!vm.surveys.isEmpty)

        // Clean up
        UserDefaults.standard.removeObject(forKey: Self.surveysKey)
    }

    @Test func loadSurveysWithValidDataLeavesPersistenceErrorNil() throws {
        // Write valid survey data to UserDefaults
        let survey = HeatmapSurvey(
            name: "Test Survey",
            mode: .freeform,
            dataPoints: [HeatmapDataPoint(x: 0.5, y: 0.5, signalStrength: -55)]
        )
        let data = try JSONEncoder().encode([survey])
        UserDefaults.standard.set(data, forKey: Self.surveysKey)

        let vm = WiFiHeatmapToolViewModel(service: StubHeatmapService())

        #expect(vm.persistenceError == nil)
        #expect(vm.surveys.count == 1)
        #expect(vm.surveys.first?.name == "Test Survey")

        // Clean up
        UserDefaults.standard.removeObject(forKey: Self.surveysKey)
    }

    @Test func deleteSurveyAndSaveLeavesNoPersistenceError() {
        // Start clean
        UserDefaults.standard.removeObject(forKey: Self.surveysKey)

        let service = StubHeatmapService()
        let vm = WiFiHeatmapToolViewModel(service: service)

        // Create a survey
        vm.startSurvey()
        vm.recordDataPoint(at: CGPoint(x: 25, y: 25), in: CGSize(width: 100, height: 100))
        vm.stopSurvey()

        guard let survey = vm.surveys.first else {
            Issue.record("Expected at least one survey after stopping")
            return
        }

        // Delete should also trigger saveSurveys without error
        vm.deleteSurvey(survey)
        #expect(vm.persistenceError == nil)

        // Clean up
        UserDefaults.standard.removeObject(forKey: Self.surveysKey)
    }
}
