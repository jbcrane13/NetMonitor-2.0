import Testing
import Foundation
@testable import NetMonitorCore

/// The troubleshooter's symptom reading (#451): the model sorts the symptom into a kind and copies
/// the user's words; the app keeps a copied phrase only when the user typed it.
@Suite("SymptomIntent")
struct SymptomIntentTests {
    @Test func aKnownKindKeepsPhrasesTheUserTyped() {
        let intent = SymptomIntent.normalized(
            kind: "deviceUnreachable", devicePhrase: "the printer", room: "office", host: nil,
            input: "The printer in the office won't print"
        )
        #expect(intent == SymptomIntent(kind: .deviceUnreachable, devicePhrase: "the printer", room: "office"))
    }

    @Test func unsupportedDropsEveryOtherField() {
        let intent = SymptomIntent.normalized(
            kind: "unsupported", devicePhrase: "weather", room: "kitchen", host: "weather.com",
            input: "what's the weather in the kitchen on weather.com"
        )
        #expect(intent == .unsupported)
    }

    @Test func anUnknownKindIsUnsupported() {
        #expect(SymptomIntent.normalized(kind: "haiku", devicePhrase: nil, room: nil, host: nil, input: "x") == .unsupported)
    }

    @Test func aHostTheUserDidNotTypeIsDropped() {
        // "Netflix won't load" must not become a host the model made up.
        let intent = SymptomIntent.normalized(
            kind: "websiteNotLoading", devicePhrase: nil, room: nil, host: "netflix.com", input: "Netflix won't load"
        )
        #expect(intent == SymptomIntent(kind: .websiteNotLoading))
    }

    @Test func aTypedHostIsKeptLowercased() {
        let intent = SymptomIntent.normalized(
            kind: "websiteNotLoading", devicePhrase: nil, room: nil, host: "GitHub.com", input: "github.com won't open"
        )
        #expect(intent.host == "github.com")
    }

    @Test func aDevicePhraseWithWordsTheUserDidNotTypeIsDropped() {
        let intent = SymptomIntent.normalized(
            kind: "deviceUnreachable", devicePhrase: "Brother printer", room: "", host: "",
            input: "can't reach the printer"
        )
        #expect(intent == SymptomIntent(kind: .deviceUnreachable))
    }

    @Test func fieldsAKindDoesNotUseAreDropped() {
        let intent = SymptomIntent.normalized(
            kind: "slowOrUnstableInternet", devicePhrase: "zoom", room: "bedroom", host: "zoom.us",
            input: "Zoom keeps freezing in the bedroom on zoom.us"
        )
        #expect(intent == SymptomIntent(kind: .slowOrUnstableInternet, room: "bedroom"))
    }

    @Test func theFourPickableKindsLeaveOutUnsupported() {
        #expect(SymptomKind.pickable == [.slowOrUnstableInternet, .deviceUnreachable, .weakWiFi, .websiteNotLoading])
    }

    @Test func aStubClassifierMapsTextThroughItsTable() async {
        let classifier = FixedSymptomClassifier(intents: ["zoom keeps freezing": SymptomIntent(kind: .slowOrUnstableInternet)])
        #expect(await classifier.classify("Zoom keeps freezing") == SymptomIntent(kind: .slowOrUnstableInternet))
        #expect(await classifier.classify("write a haiku") == .unsupported)
    }

    @Test func theUnavailableClassifierIsNeverAvailable() async {
        let classifier = UnavailableSymptomClassifier()
        #expect(!classifier.isAvailable)
        #expect(await classifier.classify("Zoom keeps freezing") == nil)
    }

    @Test("a website must be a whole name the user typed: ample.com is not in example.com (#586)")
    func hostIsAWholeName() {
        func host(_ host: String, _ input: String) -> String? {
            SymptomIntent.normalized(kind: "websiteNotLoading", devicePhrase: nil, room: nil, host: host, input: input).host
        }
        #expect(host("ample.com", "example.com won't load") == nil)
        #expect(host("example.co", "example.com won't load") == nil)
        #expect(host("example.com", "Is example.com down?") == "example.com")
        #expect(host("example.com", "I can't open example.com.") == "example.com")
        #expect(host("github.com", "github.com won't open") == "github.com")
        #expect(host("https://example.com/login", "https://example.com/login won't load") == "example.com", "a copied URL counts by its host")
        #expect(host("https://ample.com/login", "https://example.com/login won't load") == nil)
        // A leading www. is the same site for grounding, but the host checked is the one typed.
        #expect(host("nytimes.com", "www.nytimes.com won't load") == "www.nytimes.com")
        #expect(host("www.nytimes.com", "nytimes.com won't load") == "nytimes.com")
        #expect(host("https://www.foo.com/login", "https://www.foo.com/login won't load") == "www.foo.com")
        #expect(host("ample.com", "www.example.com won't load") == nil)
        #expect(host("times.com", "www.nytimes.com won't load") == nil)
    }
}
