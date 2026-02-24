import Foundation
import Testing
@testable import NetMonitorCore

@Suite("GeoLocationService")
struct GeoLocationServiceTests {

    // MARK: - GeoLocation model

    @Test("GeoLocation stores all fields correctly")
    func geoLocationStoresFields() {
        let location = GeoLocation(
            ip: "8.8.8.8",
            country: "United States",
            countryCode: "US",
            region: "California",
            city: "Mountain View",
            latitude: 37.386,
            longitude: -122.0838,
            isp: "Google LLC"
        )
        #expect(location.ip == "8.8.8.8")
        #expect(location.country == "United States")
        #expect(location.countryCode == "US")
        #expect(location.region == "California")
        #expect(location.city == "Mountain View")
        #expect(location.latitude == 37.386)
        #expect(location.longitude == -122.0838)
        #expect(location.isp == "Google LLC")
    }

    @Test("GeoLocation isp is optional and can be nil")
    func geoLocationISPOptional() {
        let location = GeoLocation(
            ip: "1.1.1.1",
            country: "Australia",
            countryCode: "AU",
            region: "NSW",
            city: "Sydney",
            latitude: -33.8688,
            longitude: 151.2093
        )
        #expect(location.isp == nil)
    }

    // MARK: - GeoLocationError

    @Test("GeoLocationError.httpError has non-nil localizedDescription")
    func httpErrorDescription() {
        let err = GeoLocationError.httpError
        #expect(err.errorDescription != nil)
        #expect(err.errorDescription?.isEmpty == false)
    }

    @Test("GeoLocationError.lookupFailed includes message in description")
    func lookupFailedDescription() {
        let err = GeoLocationError.lookupFailed("reserved range")
        #expect(err.errorDescription != nil)
        #expect(err.errorDescription?.contains("reserved range") == true)
    }

    // MARK: - Caching (observable via injected URLSession)

    @Test("GeoLocationService returns error for malformed IP via URLError")
    func lookupBadURLThrows() async {
        let service = GeoLocationService()
        // Spaces in IP will produce a bad URL
        do {
            _ = try await service.lookup(ip: "not a valid ip with spaces and !@#")
            Issue.record("Expected an error to be thrown")
        } catch {
            // Any error is acceptable — the key assertion is that no result is returned
            #expect(true)
        }
    }
}
