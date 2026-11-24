import Foundation
import NetMonitorCore

// Each prompt with the kinds that count as correct.
let prompts: [(String, Set<SymptomKind>)] = [
    // The spike's #451/#452 prompts
    ("Zoom keeps freezing", [.slowOrUnstableInternet]),
    ("the printer won't print", [.deviceUnreachable]),
    ("is my Wi-Fi weak in the bedroom", [.weakWiFi]),
    ("What joined this week?", [.unsupported]),
    ("Is the printer up?", [.deviceUnreachable, .unsupported]),
    ("Which devices have been flaky?", [.unsupported, .deviceUnreachable]),
    ("Why is the internet slow tonight?", [.slowOrUnstableInternet]),
    ("Can my laptop resolve github.com?", [.websiteNotLoading, .unsupported]),
    ("How has the NAS latency been today?", [.unsupported, .deviceUnreachable]),
    ("Write me a haiku about routers.", [.unsupported]),
    // Five of mine
    ("Netflix keeps buffering on the TV", [.slowOrUnstableInternet]),
    ("can't reach the NAS from my laptop", [.deviceUnreachable]),
    ("github.com won't load", [.websiteNotLoading]),
    ("only one bar of wifi in the garage", [.weakWiFi]),
    ("what's the weather tomorrow?", [.unsupported]),
    // Extra valid symptoms, to check the escape doesn't over-reject
    ("video calls keep dropping", [.slowOrUnstableInternet]),
    ("my printer is offline", [.deviceUnreachable]),
    ("the wifi in the kitchen is terrible", [.weakWiFi]),
    ("gaming is super laggy tonight", [.slowOrUnstableInternet]),
    ("the security camera stopped responding", [.deviceUnreachable]),
    ("apple.com won't open", [.websiteNotLoading]),
]

let mode = CommandLine.arguments.dropFirst().first ?? "classify"
let classifier = SymptomClassifier.make()
print("available:", classifier.isAvailable)
if mode == "classify" {
    var ok = 0
    for (text, allowed) in prompts {
        let start = Date()
        let intent = await classifier.classify(text)
        let pass = intent.map { allowed.contains($0.kind) } ?? false
        if pass { ok += 1 }
        print(String(format: "%@ %.2fs | %@ -> %@", pass ? "PASS" : "FAIL", Date().timeIntervalSince(start), text, String(describing: intent)))
    }
    print("score \(ok)/\(prompts.count)")
}

if mode == "explain" {
    let fixtures: [(String, SymptomKind, [TroubleshootResult])] = [
        ("A: Zoom freezing, weak signal + router loss", .slowOrUnstableInternet, [
            .ping(PingSummary(target: .gateway, sent: 10, received: 9, averageMs: 4, jitterMs: 1.2)),
            .dns(host: "apple.com", milliseconds: 38),
            .wifi([WiFiReading(rssi: -80, noise: -92)]),
            .speed(downloadMbps: 85, baselineMbps: 90)
        ]),
        ("B: printer unreachable, router fine", .deviceUnreachable, [
            .ping(PingSummary(target: .device("Office Printer", "192.168.1.30"), sent: 5, received: 0, averageMs: nil, jitterMs: nil)),
            .ports(host: "192.168.1.30", open: [], closed: [631, 9100]),
            .ping(PingSummary(target: .gateway, sent: 5, received: 5, averageMs: 3, jitterMs: 0.8))
        ]),
        ("C: slow internet, slow DNS + ISP slow", .slowOrUnstableInternet, [
            .ping(PingSummary(target: .gateway, sent: 10, received: 10, averageMs: 3, jitterMs: 0.5)),
            .dns(host: "apple.com", milliseconds: 640),
            .wifi([WiFiReading(rssi: -55, noise: -95)]),
            .speed(downloadMbps: 12.4, baselineMbps: 210)
        ]),
        ("D: weak Wi-Fi, nothing found", .weakWiFi, [
            .wifi([WiFiReading(rssi: -58, noise: -93)]),
            .wifi([WiFiReading(rssi: -60, noise: -93), WiFiReading(rssi: -59, noise: -92), WiFiReading(rssi: -61, noise: -93)])
        ]),
    ]
    for (name, kind, results) in fixtures {
        let findings = TroubleshootRules.findings(for: results, completed: true)
        guard let report = TroubleshootReportBuilder.report(for: kind, findings: findings) else { continue }
        print("=== \(name)")
        print("findings:", findings.map(\.title))
        print("prompt:\n" + report.request.prompt)
        // The raw answer, then the shipped checks.
        var raw = ""
        for await update in InsightService.shared.explain(report.request) {
            if case let .finished(t) = update { raw = t }
        }
        print("raw:", raw)
        let start = Date()
        let summary = await InsightSummarizer.summary(for: report.request, service: InsightService.shared, timeout: .seconds(15))
        let shown = summary.flatMap { report.accepts($0) ? $0 : nil }
        print(String(format: "summarizer %.2fs: %@", Date().timeIntervalSince(start), summary ?? "nil (dropped)"))
        print("accepts subject:", summary.map(report.accepts) ?? false, "-> SHOWN:", shown ?? "nothing (findings only)")
    }
}
