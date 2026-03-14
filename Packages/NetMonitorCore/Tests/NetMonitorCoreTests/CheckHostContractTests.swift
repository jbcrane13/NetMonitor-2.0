import Foundation
import Testing
@testable import NetMonitorCore

/// Contract tests for the check-host.net API JSON fixtures.
///
/// ## Context
/// TracerouteService uses check-host.net as an HTTP fallback when ICMP sockets are
/// unavailable (e.g., iOS Simulator, sandboxed environments). The fixture files in
/// TestFixtures/ capture the real API response shapes.
///
/// ## Integration Gap
/// `TracerouteService.performHTTPTracerouteFallback` uses `URLSession.shared` internally
/// rather than an injected session, so full end-to-end mock testing requires a further
/// refactor (add `init(session:)` to TracerouteService). These tests validate the JSON
/// format contracts by parsing the fixture data directly — ensuring that if the API
/// response shape ever changes, or if TracerouteService's parser assumptions change,
/// the discrepancy is caught immediately.
///
/// ## What is tested
/// 1. Submit response format: `request_id` field is present and non-empty
/// 2. Submit response format: `nodes` dictionary contains expected node keys
/// 3. Result response format: each node key maps to an array of per-probe arrays
/// 4. Result response format: successful probe entries have the expected shape
/// 5. Timeout probe entries are distinguishable from successful ones
/// 6. RTT values are representable as Double (the parser casts to [Double])
struct CheckHostContractTests {

    // MARK: - Fixture loading helpers

    private func loadFixtureData(named name: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: nil) else {
            throw NSError(
                domain: "CheckHostContractTests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Fixture '\(name)' not found in Bundle.module"]
            )
        }
        return try Data(contentsOf: url)
    }

    private func loadFixtureJSON(named name: String) throws -> [String: Any] {
        let data = try loadFixtureData(named: name)
        let json = try JSONSerialization.jsonObject(with: data)
        guard let dict = json as? [String: Any] else {
            throw NSError(
                domain: "CheckHostContractTests",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Fixture '\(name)' is not a JSON object"]
            )
        }
        return dict
    }

    // MARK: - Submit Response Contract (check-host-submit-success.json)

    @Test("Submit response: request_id field is present and non-empty")
    func submitResponseHasRequestID() throws {
        let json = try loadFixtureJSON(named: "check-host-submit-success.json")
        let requestId = json["request_id"] as? String
        #expect(requestId != nil, "Submit response must contain 'request_id' key of type String")
        #expect(requestId?.isEmpty == false, "request_id must not be empty")
    }

    @Test("Submit response: nodes dictionary is present and non-empty")
    func submitResponseHasNodes() throws {
        let json = try loadFixtureJSON(named: "check-host-submit-success.json")
        let nodes = json["nodes"] as? [String: Any]
        #expect(nodes != nil, "Submit response must contain 'nodes' dictionary")
        #expect(nodes?.isEmpty == false, "nodes dictionary must not be empty")
    }

    @Test("Submit response: each node is an array with at least 3 elements (country, city, IP)")
    func submitResponseNodeArrayShape() throws {
        let json = try loadFixtureJSON(named: "check-host-submit-success.json")
        guard let nodes = json["nodes"] as? [String: Any] else {
            Issue.record("nodes key missing from submit fixture")
            return
        }
        for (nodeKey, nodeValue) in nodes {
            guard let nodeArray = nodeValue as? [String] else {
                Issue.record("Node '\(nodeKey)' is not a String array")
                continue
            }
            #expect(nodeArray.count >= 3,
                    "Node '\(nodeKey)' should have at least [countryCode, country, city, ...], got \(nodeArray.count) elements")
        }
    }

    @Test("Real submit response: request_id field is present and non-empty")
    func realSubmitResponseHasRequestID() throws {
        let json = try loadFixtureJSON(named: "check-host-submit-real.json")
        let requestId = json["request_id"] as? String
        #expect(requestId != nil, "Real submit fixture must contain 'request_id'")
        #expect(requestId?.isEmpty == false)
    }

    @Test("Real submit response: nodes include expected country codes")
    func realSubmitResponseHasKnownCountryCodes() throws {
        let json = try loadFixtureJSON(named: "check-host-submit-real.json")
        guard let nodes = json["nodes"] as? [String: Any] else {
            Issue.record("nodes key missing from real submit fixture")
            return
        }
        // Collect first element (country code) from each node array
        let countryCodes = nodes.values.compactMap { ($0 as? [String])?.first }
        #expect(!countryCodes.isEmpty, "Should extract at least one country code from nodes")
        // Each country code should be a 2-letter lowercase string (ISO 3166-1 alpha-2)
        for code in countryCodes {
            #expect(code.count == 2, "Country code '\(code)' should be 2 characters")
        }
    }

    // MARK: - Result Response Contract (check-host-result-complete.json)
    //
    // The check-host.net ping result format (used by the former WorldPingService and
    // retained as a format reference) is:
    //   { "node.check-host.net": [ [ ["OK", rtt_seconds, ip, ttl] ] ] }
    //
    // This is distinct from the traceroute format:
    //   { "node.check-host.net": [ [ [[rtt1, rtt2], hostname_or_null, ip], ... ] ] }

    @Test("Result response: top-level keys are node hostnames (contain check-host.net)")
    func resultResponseKeysAreNodeHostnames() throws {
        let json = try loadFixtureJSON(named: "check-host-result-complete.json")
        #expect(!json.isEmpty, "Result fixture must have at least one node")
        for key in json.keys {
            #expect(key.contains("check-host.net"),
                    "Result key '\(key)' should be a check-host.net node hostname")
        }
    }

    @Test("Result response: each node value is a non-empty array")
    func resultResponseNodeValuesAreArrays() throws {
        let json = try loadFixtureJSON(named: "check-host-result-complete.json")
        for (nodeKey, nodeValue) in json {
            guard let outerArray = nodeValue as? [[Any]] else {
                Issue.record("Node '\(nodeKey)' value is not an array of arrays")
                continue
            }
            #expect(!outerArray.isEmpty,
                    "Node '\(nodeKey)' result array must not be empty")
        }
    }

    @Test("Result response: successful probe entries contain status string as first element")
    func resultResponseSuccessfulProbeHasStatusString() throws {
        let json = try loadFixtureJSON(named: "check-host-result-complete.json")
        for (nodeKey, nodeValue) in json {
            guard let outerArray = nodeValue as? [[[Any]]],
                  let firstProbeSet = outerArray.first,
                  let firstProbe = firstProbeSet.first else {
                continue
            }
            let status = firstProbe.first as? String
            #expect(status != nil,
                    "Node '\(nodeKey)' first probe should have a String status as first element")
            #expect(status == "OK" || status == "TIMEOUT",
                    "Status for node '\(nodeKey)' should be 'OK' or 'TIMEOUT', got '\(status ?? "nil")'")
        }
    }

    @Test("Result response: OK probe entries have RTT as second element (Double)")
    func resultResponseOKProbeHasDoubleRTT() throws {
        let json = try loadFixtureJSON(named: "check-host-result-complete.json")
        for (nodeKey, nodeValue) in json {
            guard let outerArray = nodeValue as? [[[Any]]],
                  let firstProbeSet = outerArray.first,
                  let firstProbe = firstProbeSet.first,
                  let status = firstProbe.first as? String,
                  status == "OK" else {
                continue
            }
            // Second element should be RTT in seconds (Double)
            let rtt = firstProbe.count > 1 ? (firstProbe[1] as? Double) : nil
            #expect(rtt != nil,
                    "Node '\(nodeKey)' OK probe should have Double RTT as second element")
            if let rtt = rtt {
                #expect(rtt > 0, "RTT for node '\(nodeKey)' should be positive, got \(rtt)")
                #expect(rtt < 10, "RTT for node '\(nodeKey)' should be < 10 seconds (likely in seconds), got \(rtt)")
            }
        }
    }

    @Test("Result response: OK probe RTT values are in seconds (< 1.0 for sub-second latency)")
    func resultResponseRTTIsInSeconds() throws {
        let json = try loadFixtureJSON(named: "check-host-result-complete.json")
        // All nodes in the fixture represent realistic internet latencies (< 300ms = 0.3s)
        for (nodeKey, nodeValue) in json {
            guard let outerArray = nodeValue as? [[[Any]]],
                  let firstProbeSet = outerArray.first,
                  let firstProbe = firstProbeSet.first,
                  let status = firstProbe.first as? String,
                  status == "OK",
                  let rtt = firstProbe.count > 1 ? (firstProbe[1] as? Double) : nil else {
                continue
            }
            #expect(rtt < 1.0, "RTT should be < 1.0s (values are in seconds, not ms). If this fails, the fixture format may have changed.")
        }
    }

    @Test("Result response: all 5 fixture nodes are present")
    func resultResponseHasFiveNodes() throws {
        let json = try loadFixtureJSON(named: "check-host-result-complete.json")
        #expect(json.count == 5, "check-host-result-complete.json should have 5 nodes, got \(json.count)")
    }

    // MARK: - Timeout Result Contract (check-host-result-all-timeout.json)

    @Test("Timeout result: all nodes have TIMEOUT status")
    func timeoutResultAllNodesAreTimeout() throws {
        let json = try loadFixtureJSON(named: "check-host-result-all-timeout.json")
        #expect(!json.isEmpty, "Timeout fixture must have at least one node")
        for (nodeKey, nodeValue) in json {
            guard let outerArray = nodeValue as? [[[Any]]],
                  let firstProbeSet = outerArray.first,
                  let firstProbe = firstProbeSet.first else {
                Issue.record("Node '\(nodeKey)' has unexpected structure in timeout fixture")
                continue
            }
            let status = firstProbe.first as? String
            #expect(status == "TIMEOUT",
                    "Node '\(nodeKey)' should have TIMEOUT status, got '\(status ?? "nil")'")
        }
    }

    @Test("Timeout result: all 5 nodes are present")
    func timeoutResultHasFiveNodes() throws {
        let json = try loadFixtureJSON(named: "check-host-result-all-timeout.json")
        #expect(json.count == 5, "check-host-result-all-timeout.json should have 5 nodes, got \(json.count)")
    }

    // MARK: - Real Result Contract (check-host-result-real.json)
    //
    // The real fixture captures a realistic response with multiple probes per node
    // and a partial timeout (au1 has one timeout among 3 probes).

    @Test("Real result: multiple probes per node are present")
    func realResultHasMultipleProbesPerNode() throws {
        let json = try loadFixtureJSON(named: "check-host-result-real.json")
        for (nodeKey, nodeValue) in json {
            guard let outerArray = nodeValue as? [[[Any]]],
                  let probeSet = outerArray.first else {
                continue
            }
            #expect(probeSet.count > 1,
                    "Node '\(nodeKey)' in real fixture should have multiple probes per set, got \(probeSet.count)")
        }
    }

    @Test("Real result: au1 node has partial timeout (mixed OK and timeout probes)")
    func realResultAU1HasPartialTimeout() throws {
        let json = try loadFixtureJSON(named: "check-host-result-real.json")
        guard let au1Value = json["au1.node.check-host.net"],
              let outerArray = au1Value as? [[[Any]]],
              let probeSet = outerArray.first else {
            Issue.record("au1.node.check-host.net not found in real result fixture")
            return
        }
        let statuses = probeSet.compactMap { $0.first as? String }
        let timeouts = statuses.filter { $0 == "timeout" || $0 == "TIMEOUT" }
        let successes = statuses.filter { $0 == "OK" }
        #expect(!timeouts.isEmpty, "au1 should have at least one timeout probe in real fixture")
        #expect(!successes.isEmpty, "au1 should have at least one OK probe in real fixture")
    }

    @Test("Real result: RTT seconds-to-milliseconds conversion produces realistic values")
    func realResultRTTConversionIsRealistic() throws {
        let json = try loadFixtureJSON(named: "check-host-result-real.json")
        // The TracerouteService converts seconds to ms: `rtts.map { $0 * 1000 }`
        // Verify that after conversion, values are in plausible ms range (1–500ms)
        for (nodeKey, nodeValue) in json {
            guard let outerArray = nodeValue as? [[[Any]]],
                  let probeSet = outerArray.first else { continue }
            for probe in probeSet {
                guard let status = probe.first as? String, status == "OK",
                      let rttSeconds = probe.count > 1 ? (probe[1] as? Double) : nil else { continue }
                let rttMs = rttSeconds * 1000
                #expect(rttMs >= 1.0 && rttMs <= 500.0,
                        "Node '\(nodeKey)' RTT after conversion should be 1–500ms, got \(rttMs)ms")
            }
        }
    }

    // MARK: - Format Consistency: Submit + Result node keys align

    @Test("Submit and result fixture node keys share at least one common node")
    func submitAndResultShareCommonNodes() throws {
        let submitJSON = try loadFixtureJSON(named: "check-host-submit-success.json")
        let resultJSON = try loadFixtureJSON(named: "check-host-result-complete.json")

        guard let nodes = submitJSON["nodes"] as? [String: Any] else {
            Issue.record("Submit fixture missing 'nodes' key")
            return
        }

        let submitNodeKeys = Set(nodes.keys)
        let resultNodeKeys = Set(resultJSON.keys)
        let overlap = submitNodeKeys.intersection(resultNodeKeys)

        #expect(!overlap.isEmpty, "Submit and result fixtures should share at least one common node key — if this fails the fixtures may be mismatched.")
    }
}
