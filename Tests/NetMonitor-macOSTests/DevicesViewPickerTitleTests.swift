import Testing
@testable import NetMonitor_macOS

/// #425: the network picker sizes to its title, so long names are shortened.
struct DevicesViewPickerTitleTests {

    @Test("Short network names are unchanged")
    func shortNameUnchanged() {
        #expect(DevicesView.pickerTitle("Wi-Fi") == "Wi-Fi")
        #expect(DevicesView.pickerTitle(String(repeating: "a", count: 24)) == String(repeating: "a", count: 24))
    }

    @Test("Long network names are cut to the limit with an ellipsis")
    func longNameTruncated() {
        let title = DevicesView.pickerTitle("Wi-Fi — 192.168.2.0/24 (Upstairs Office)")
        #expect(title.count == 24)
        #expect(title.hasSuffix("…"))
        #expect(title.hasPrefix("Wi-Fi — 192.168.2.0/24"))
    }
}
