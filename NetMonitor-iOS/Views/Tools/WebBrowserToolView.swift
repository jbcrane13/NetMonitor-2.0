import SwiftUI
import NetMonitorCore
import SafariServices

/// Web Browser tool for network-related web browsing and testing
struct WebBrowserToolView: View {
    @State private var urlText: String = ""
    @State private var showingSafari = false
    @State private var recentURLs: [String] = []
    @State private var routerAdminURL: String = "http://192.168.1.1"

    private var quickBookmarks: [BookmarkItem] {
        [
            BookmarkItem(name: "Router Admin", url: routerAdminURL, icon: "wifi.router", description: "Access router settings"),
            BookmarkItem(name: "Speed Test", url: "https://speed.cloudflare.com", icon: "speedometer", description: "Cloudflare speed test"),
            BookmarkItem(name: "DNS Checker", url: "https://dns.google", icon: "globe", description: "Google DNS tools"),
            BookmarkItem(name: "What's My IP", url: "https://whatismyipaddress.com", icon: "location", description: "Check public IP"),
            BookmarkItem(name: "Port Checker", url: "https://www.yougetsignal.com/tools/open-ports/", icon: "door.left.hand.open", description: "Test port connectivity"),
            BookmarkItem(name: "Ping Test", url: "https://tools.pingdom.com", icon: "arrow.up.arrow.down", description: "Online ping tools")
        ]
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Layout.sectionSpacing) {
                urlInputSection
                quickBookmarksSection
                if !recentURLs.isEmpty {
                    recentURLsSection
                }
            }
            .padding(.horizontal, Theme.Layout.screenPadding)
            .padding(.bottom, Theme.Layout.sectionSpacing)
        }
        .themedBackground()
        .navigationTitle("Web Browser")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .accessibilityIdentifier("screen_webBrowser")
        .sheet(isPresented: $showingSafari) {
            if let url = validURL(from: urlText) {
                SafariView(url: url) {
                    addToRecentURLs(urlText)
                }
            }
        }
        .onAppear {
            loadRecentURLs()
            detectRouterAddress()
        }
    }
    
    // MARK: - URL Input Section
    
    private var urlInputSection: some View {
        VStack(alignment: .leading, spacing: Theme.Layout.itemSpacing) {
            Text("Enter URL")
                .font(.headline)
                .foregroundStyle(Theme.Colors.textPrimary)
            
            ToolInputField(
                text: $urlText,
                placeholder: "https://example.com or 192.168.1.1",
                icon: "globe",
                keyboardType: .URL,
                accessibilityID: "webBrowser_input_url",
                onSubmit: {
                    openURL()
                }
            )
            
            ToolRunButton(
                title: "Open URL",
                icon: "safari.fill",
                isRunning: false,
                action: openURL
            )
            .disabled(urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityIdentifier("webBrowser_button_open")
        }
    }
    
    // MARK: - Quick Bookmarks Section
    
    private var quickBookmarksSection: some View {
        VStack(alignment: .leading, spacing: Theme.Layout.itemSpacing) {
            Text("Network Tools & Common Sites")
                .font(.headline)
                .foregroundStyle(Theme.Colors.textPrimary)
            
            GlassCard {
                VStack(spacing: 0) {
                    ForEach(Array(quickBookmarks.enumerated()), id: \.element.id) { index, bookmark in
                        BookmarkRow(bookmark: bookmark) {
                            urlText = bookmark.url
                            openURL()
                        }
                        
                        if index < quickBookmarks.count - 1 {
                            Divider()
                                .background(Theme.Colors.glassBorder)
                                .padding(.vertical, 8)
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("webBrowser_section_bookmarks")
    }
    
    // MARK: - Recent URLs Section
    
    @ViewBuilder
    private var recentURLsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Layout.itemSpacing) {
            HStack {
                Text("Recent URLs")
                    .font(.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                
                Spacer()
                
                Button("Clear") {
                    recentURLs.removeAll()
                    saveRecentURLs()
                }
                .font(.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .accessibilityIdentifier("webBrowser_button_clearRecent")
            }
            
            GlassCard {
                VStack(spacing: 0) {
                    ForEach(Array(recentURLs.enumerated()), id: \.offset) { index, url in
                        RecentURLRow(url: url) {
                            urlText = url
                            openURL()
                        }
                        
                        if index < recentURLs.count - 1 {
                            Divider()
                                .background(Theme.Colors.glassBorder)
                                .padding(.vertical, 8)
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("webBrowser_section_recent")
    }
    
    // MARK: - Actions
    
    private func openURL() {
        guard !urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        showingSafari = true
    }
    
    private func validURL(from text: String) -> URL? {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Try as-is first (for full URLs)
        if let url = URL(string: trimmedText), url.scheme != nil {
            return url
        }
        
        // Try with https:// prefix
        if let url = URL(string: "https://" + trimmedText), url.host != nil {
            return url
        }
        
        // Try with http:// prefix (for local network devices)
        if let url = URL(string: "http://" + trimmedText), url.host != nil {
            return url
        }
        
        return nil
    }
    
    private func addToRecentURLs(_ url: String) {
        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove if already exists
        recentURLs.removeAll { $0 == trimmedURL }
        
        // Add to beginning
        recentURLs.insert(trimmedURL, at: 0)
        
        // Keep only last 10
        if recentURLs.count > 10 {
            recentURLs = Array(recentURLs.prefix(10))
        }
        
        saveRecentURLs()
    }
    
    private func loadRecentURLs() {
        if let data = UserDefaults.standard.data(forKey: AppSettings.Keys.webBrowserRecentURLs),
           let urls = try? JSONDecoder().decode([String].self, from: data) {
            recentURLs = urls
        }
    }
    
    private func saveRecentURLs() {
        if let data = try? JSONEncoder().encode(recentURLs) {
            UserDefaults.standard.set(data, forKey: AppSettings.Keys.webBrowserRecentURLs)
        }
    }

    private func detectRouterAddress() {
        if let gateway = NetworkUtilities.detectDefaultGateway() {
            routerAdminURL = "http://\(gateway)"
        }
    }
}

// MARK: - Supporting Views

struct BookmarkItem: Identifiable {
    var id: String { url }
    let name: String
    let url: String
    let icon: String
    let description: String
}

struct BookmarkRow: View {
    let bookmark: BookmarkItem
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: bookmark.icon)
                    .font(.title3)
                    .foregroundStyle(Theme.Colors.accent)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(bookmark.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(Theme.Colors.textPrimary)

                    Text(bookmark.description)
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)

                    Text(bookmark.url)
                        .font(.caption)
                        .fontDesign(.monospaced)
                        .foregroundStyle(Theme.Colors.textTertiary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
            .accessibilityIdentifier("webBrowser_bookmark_\(bookmark.name.lowercased().replacingOccurrences(of: " ", with: "_"))")
        }
        .buttonStyle(.plain)
    }
}

struct RecentURLRow: View {
    let url: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "clock.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .frame(width: 16)
                
                Text(url)
                    .font(.caption)
                    .fontDesign(.monospaced)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("webBrowser_recent_url")
    }
}

// MARK: - Safari View Controller Wrapper

struct SafariView: UIViewControllerRepresentable {
    let url: URL
    let onDismiss: () -> Void
    
    func makeUIViewController(context: Context) -> SFSafariViewController {
        let safariVC = SFSafariViewController(url: url)
        safariVC.delegate = context.coordinator
        return safariVC
    }
    
    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {
        // No updates needed
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onDismiss: onDismiss)
    }
    
    class Coordinator: NSObject, SFSafariViewControllerDelegate {
        let onDismiss: () -> Void
        
        init(onDismiss: @escaping () -> Void) {
            self.onDismiss = onDismiss
        }
        
        func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
            onDismiss()
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        WebBrowserToolView()
    }
}
