import SwiftUI
import Network
import UserNotifications

struct OnboardingView: View {
    @Binding var isPresented: Bool
    @State private var currentPage = 0

    private let totalPages = 3

    var body: some View {
        ZStack(alignment: .top) {
            Theme.Colors.backgroundBase
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Skip button
                HStack {
                    Spacer()
                    if currentPage < totalPages - 1 {
                        Button("Skip") {
                            completeOnboarding()
                        }
                        .font(.subheadline)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .padding(.horizontal, Theme.Layout.screenPadding)
                        .padding(.top, 16)
                        .accessibilityIdentifier("onboarding_button_skip")
                    }
                }
                .frame(height: 44)

                TabView(selection: $currentPage) {
                    WelcomePage()
                        .tag(0)

                    NetworkAccessPage()
                        .tag(1)

                    NotificationsPage()
                        .tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))
                .animation(Theme.Animation.standard, value: currentPage)

                // Continue / Get Started button
                VStack(spacing: 16) {
                    Button {
                        if currentPage < totalPages - 1 {
                            withAnimation(Theme.Animation.standard) {
                                currentPage += 1
                            }
                        } else {
                            completeOnboarding()
                        }
                    } label: {
                        Text(currentPage < totalPages - 1 ? "Continue" : "Get Started")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Theme.Colors.accent)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.buttonCornerRadius))
                    }
                    .accessibilityIdentifier(currentPage < totalPages - 1 ? "onboarding_button_continue" : "onboarding_button_get_started")
                    .padding(.horizontal, Theme.Layout.screenPadding)
                }
                .padding(.bottom, 32)
            }
        }
    }

    private func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        isPresented = false
    }
}

// MARK: - Welcome Page

private struct WelcomePage: View {
    var body: some View {
        OnboardingPageView(
            icon: "wifi",
            title: "Welcome to NetMonitor",
            description: "Monitor your network, discover connected devices, run diagnostics, and stay informed about everything happening on your local network.",
            accessibilityPrefix: "onboarding_welcome"
        )
    }
}

// MARK: - Network Access Page

private struct NetworkAccessPage: View {
    var body: some View {
        OnboardingPageView(
            icon: "network",
            title: "Network Access Required",
            description: "NetMonitor needs access to your local network to discover devices, measure latency, and provide real-time network diagnostics.",
            accessibilityPrefix: "onboarding_network",
            actionButton: OnboardingActionButton(
                label: "Allow Access",
                accessibilityID: "onboarding_button_allow_network"
            ) {
                // Starting NWPathMonitor triggers the local network permission prompt
                let monitor = NWPathMonitor()
                monitor.start(queue: DispatchQueue.global(qos: .background))
                // Brief delay then cancel — we just need the prompt to fire
                Task<Void, Never> {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    monitor.cancel()
                }
            }
        )
    }
}

// MARK: - Notifications Page

private struct NotificationsPage: View {
    var body: some View {
        OnboardingPageView(
            icon: "bell.badge",
            title: "Stay Informed",
            description: "Get notified when new devices join your network, a monitored target goes offline, or high latency is detected.",
            accessibilityPrefix: "onboarding_notifications",
            actionButton: OnboardingActionButton(
                label: "Enable Notifications",
                accessibilityID: "onboarding_button_enable_notifications"
            ) {
                Task<Void, Never> {
                    _ = try? await UNUserNotificationCenter.current()
                        .requestAuthorization(options: [.alert, .badge, .sound])
                }
            }
        )
    }
}

// MARK: - Reusable Page Layout

private struct OnboardingActionButton {
    let label: String
    let accessibilityID: String
    let action: () -> Void
}

private struct OnboardingPageView: View {
    let icon: String
    let title: String
    let description: String
    let accessibilityPrefix: String
    var actionButton: OnboardingActionButton?

    var body: some View {
        VStack(spacing: Theme.Layout.sectionSpacing) {
            Spacer()

            Image(systemName: icon)
                .font(.system(size: 80, weight: .light))
                .foregroundStyle(Theme.Colors.accent)
                .accessibilityIdentifier("\(accessibilityPrefix)_icon")

            VStack(spacing: Theme.Layout.itemSpacing) {
                Text(title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("\(accessibilityPrefix)_title")

                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .accessibilityIdentifier("\(accessibilityPrefix)_description")
            }
            .padding(.horizontal, Theme.Layout.screenPadding * 2)

            if let button = actionButton {
                Button(button.label) {
                    button.action()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.Colors.accent)
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                .background(Theme.Colors.accent.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.buttonCornerRadius))
                .accessibilityIdentifier(button.accessibilityID)
            }

            Spacer()
            Spacer()
        }
    }
}

// MARK: - Preview

#Preview {
    OnboardingView(isPresented: .constant(true))
}
