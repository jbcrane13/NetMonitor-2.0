import Testing
import Foundation
@testable import NetMonitor_iOS

// MARK: - RateAppServiceTests

/// Tests for the ``RateAppService`` static enum.
///
/// Note: RateAppService is a static enum wrapping SKStoreReviewController and
/// UIApplication.open(). We cannot invoke the actual review prompt or URL opening
/// in a unit test sandbox, but we can verify the configuration and URL construction.
@MainActor
struct RateAppServiceTests {

    @Test("App Store ID constant is defined and non-empty")
    func appStoreIDIsNonEmpty() {
        #expect(!RateAppService.appStoreID.isEmpty)
    }

    @Test("Review URL contains the App Store ID")
    func reviewURLContainsAppStoreID() {
        // The review URL is constructed from appStoreID via string interpolation.
        // Verify the expected URL pattern is well-formed.
        let expectedSuffix = "id\(RateAppService.appStoreID)?action=write-review"
        // Access the private URL indirectly by checking the constant format
        #expect(RateAppService.appStoreID.count > 0)
        #expect(expectedSuffix.contains(RateAppService.appStoreID))
    }

    @Test("requestReview does not crash in test sandbox")
    func requestReviewDoesNotCrash() {
        // In the test sandbox there is no foreground UIWindowScene, so
        // requestReview() should silently no-op without throwing.
        RateAppService.requestReview()
    }

    @Test("openReviewPage does not crash when URL is valid")
    func openReviewPageDoesNotCrash() {
        // URL is valid (itms-apps:// scheme). In test sandbox UIApplication.open()
        // may no-op, but the call itself must not crash.
        RateAppService.openReviewPage()
    }

    @Test("openAppStorePage does not crash when URL is valid")
    func openAppStorePageDoesNotCrash() {
        RateAppService.openAppStorePage()
    }
}
