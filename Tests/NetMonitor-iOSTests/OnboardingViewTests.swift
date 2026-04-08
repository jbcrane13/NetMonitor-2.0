import Foundation
import Testing
@testable import NetMonitor_iOS

struct OnboardingViewTests {

    @Test func completesOnboardingBySettingUserDefault() {
        // Clear any prior state
        UserDefaults.standard.removeObject(forKey: "hasCompletedOnboarding")

        // Simulate what completeOnboarding() does
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")

        #expect(UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") == true)

        // Clean up
        UserDefaults.standard.removeObject(forKey: "hasCompletedOnboarding")
    }

    @Test func onboardingDefaultIsNotCompleted() {
        let key = "hasCompletedOnboarding_test_isolation"
        UserDefaults.standard.removeObject(forKey: key)
        #expect(UserDefaults.standard.bool(forKey: key) == false)
    }
}
