import Foundation
import NetMonitorCore

#if DEBUG
/// A public-IP/ISP stand-in for UI tests: the dashboard's WAN card shows fixture values instead of
/// waiting on an outside lookup that can be slow or rate-limited.
///
/// Enabled only in Debug builds, under `--uitesting`, with `UITEST_FAKE_ISP=1`. The whole type is
/// compiled out of Release. The values are from the documentation ranges (RFC 5737 / RFC 3849) and
/// a made-up provider, so they identify nobody.
@MainActor
@Observable
final class UITestFakeISPService: PublicIPServiceProtocol {
    static let isEnabled: Bool =
        UITestBootstrap.isUITesting && ProcessInfo.processInfo.environment["UITEST_FAKE_ISP"] == "1"

    static let ispName = "Example Test ISP"
    static let publicIP = "203.0.113.7"

    private(set) var ispInfo: ISPInfo?
    private(set) var isLoading = false

    func fetchPublicIP(forceRefresh: Bool) async {
        ispInfo = ISPInfo(
            publicIP: Self.publicIP, ispName: Self.ispName, asn: "AS64496", organization: Self.ispName,
            city: "Testville", region: "Testland", country: "Examplia", countryCode: "XX", timezone: "UTC"
        )
    }
}
#endif
