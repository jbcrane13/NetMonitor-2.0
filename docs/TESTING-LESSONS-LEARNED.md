# Testing Lessons Learned: The Mock Trap

## Date: 2026-02-24
## Project: NetMonitor 2.0

---

## Executive Summary

During a comprehensive test coverage sprint, we wrote 349 new tests across 48 files. All tests compiled and passed. Two major features (GeoTrace and World Ping) were completely broken in the real app. The tests said they worked. This document explains why, and how we've changed our testing approach to prevent it.

---

## The Incident

### What Happened

We ran `/test-coverage` to audit and fill test gaps across NetMonitor 2.0. Four parallel workers created 329 unit tests and 20 functional UI tests. Package tests passed (493 in NetMonitorCore, 151 in NetworkScanKit). iOS unit tests passed (42 suites, 0 failures).

Then we tested the actual app:
- **GeoTrace**: Shows zero trace hops. No activity at all on screen.
- **World Ping**: Shows "no response" for every single test. Zero results.

Both features appeared fully tested with passing tests.

### Root Cause: Mock-Only Coverage

Every test for these features injected **mock services** that returned fake data. The tests proved:
- The ViewModel correctly processes data it receives (plumbing works)
- The UI correctly displays data the ViewModel provides (rendering works)

The tests did NOT prove:
- The real `TracerouteService` can actually produce traceroute hops on iOS
- The real `WorldPingService` can actually get results from the check-host.net API

### The Specific Bugs

**GeoTrace (`TracerouteService`)**:
```swift
// Line 94: ICMP socket creation fails on iOS
if let socket = try? ICMPSocket() {
    // This path never executes on real iOS devices
    await performICMPTrace(...)
} else {
    // Falls back to TCP probe — returns only 1 hop, not a real traceroute
    await performTCPFallback(...)
}
```
The TCP fallback sends a single TCP SYN to port 443. It returns at most 1 hop (the destination). That's not a traceroute — it's a connectivity check. Users see either nothing or a single unhelpful dot.

**World Ping (`WorldPingService`)**:
```swift
// Line 26-28: ALL errors silently swallowed
} catch {
    // Stream ends empty on network/API errors
}
```
The API call to `check-host.net` fails (likely decode error, network policy, or API format change). The `catch {}` block eats the error. The AsyncStream yields nothing. The ViewModel receives an empty stream. The user sees a blank screen with no error message.

---

## Why Mock Tests Didn't Catch This

### The Testing Pyramid Failure

```
What we built:          What we needed:

    /\                      /\
   /UI\                    /UI\        <- UI tests (element interaction)
  /----\                  /----\
 / Unit \                /Integ\       <- Integration tests (real service + fixture data)
/--------\              /--------\
  (mocks)              / Contract \    <- Contract tests (real parser + real API response)
                      /------------\
                        (mocks)        <- Unit tests (ViewModel plumbing)
```

We built the bottom layer (mocks) and top layer (UI) but skipped the middle layers (integration and contract tests) entirely. The middle layers are what catch "tests pass, feature broken."

### Mock Test Anatomy

Here's what a typical mock test looks like:

```swift
@Test func startTraceProcessesHops() async {
    let mock = MockTracerouteService()
    mock.mockHops = [
        TracerouteHop(hopNumber: 1, ipAddress: "10.0.0.1", ...),
        TracerouteHop(hopNumber: 2, ipAddress: "8.8.8.8", ...),
    ]
    let vm = GeoTraceViewModel(tracerouteService: mock)
    vm.host = "8.8.8.8"
    vm.startTrace()
    // ... wait ...
    #expect(vm.hops.count == 2)  // PASSES! But real service returns 0 hops.
}
```

This test creates fake hops, feeds them through the ViewModel, and verifies they display. It proves the **display pipeline** works. It says nothing about whether `TracerouteService.trace()` can actually produce hops.

### What an Integration Test Would Have Caught

```swift
@Test func realTracerouteServiceProducesAtLeastOneHop() async {
    let service = TracerouteService()  // REAL service, not mock
    let stream = await service.trace(host: "8.8.8.8", maxHops: 5, timeout: 3.0)
    var hops: [TracerouteHop] = []
    for await hop in stream { hops.append(hop) }
    // This would FAIL — revealing the bug before shipping
    #expect(!hops.isEmpty, "Real traceroute should produce at least one hop")
}
```

### What a Contract Test Would Have Caught

```swift
@Test func worldPingResponseParsesCorrectly() {
    // Real recorded API response from check-host.net
    let fixture = """
    {"ok":1,"request_id":"abc123","nodes":{"us1.node":["US","New York","NY","US","1.2.3.4"]}}
    """
    let data = Data(fixture.utf8)
    // Use the REAL parser, not a mock
    let response = try JSONDecoder().decode(CheckPingResponse.self, from: data)
    #expect(response.requestId == "abc123")
    #expect(response.nodes.count == 1)
}
```

---

## The Silent Error Anti-Pattern

The most dangerous pattern we found:

```swift
// DANGEROUS: Error swallowed, user sees blank screen
do {
    let results = try await apiCall()
    for result in results { continuation.yield(result) }
} catch {
    // Stream ends empty — no error surfaced
}
continuation.finish()
```

This pattern means:
1. API call fails (for any reason)
2. Error is caught and discarded
3. AsyncStream finishes with zero items
4. ViewModel receives empty stream
5. UI shows empty state (no error message)
6. User thinks "no results" when the real issue is "broken service"

### The Fix Pattern

```swift
// SAFE: Error surfaced to user
do {
    let results = try await apiCall()
    for result in results { continuation.yield(result) }
} catch {
    // Yield an error result so the ViewModel can show it
    continuation.yield(.error(error.localizedDescription))
    // OR: set an error property on the service
    // OR: throw from the function so the caller handles it
}
continuation.finish()
```

---

## How We're Preventing This Going Forward

### Updated `/test-coverage` Command

We've added three key improvements to the test coverage audit:

#### 1. New Agent 4: Silent Failure & Integration Risk Audit

A dedicated audit agent now searches for:
- `catch { }`, `catch {}`, empty error handlers
- `try?` without error logging
- Services where mock tests exist but no real service test
- External API calls with no contract tests
- The question: "If the real service failed, would the user see an error or a blank screen?"

#### 2. New Coverage Gap Categories

| Category | Before | After |
|----------|--------|-------|
| 1. Zero coverage | Yes | Yes |
| 2. Shallow tests | Yes | Yes |
| 3. Disabled tests | Yes | Yes |
| 4. Missing unit tests | Yes | Yes |
| 5. Mock-only coverage | **No** | **Yes** |
| 6. Silent failure paths | **No** | **Yes** |
| 7. Integration gaps | **No** | **Yes** |

#### 3. New Test Type Requirements

| Service Type | Required Tests |
|-------------|---------------|
| Pure logic (calculators, parsers, formatters) | Unit tests with known inputs |
| ViewModels | Mock-based unit tests (existing approach) |
| Network API services | Contract test with recorded response fixture |
| Hardware-dependent services | Contract test for data format + documented gap |
| Services producing user-visible output | Integration test proving real service produces output |
| Any service with `catch {}` | Bug issue + error surfacing fix first |

#### 4. Revised Priority System

- **P0** = Silent failures + mock-only features (tests pass, feature broken)
- **P1** = Zero coverage flows
- **P2** = Shallow-only coverage
- **P3** = Disabled tests

Previously, "mock-only coverage" was invisible — it looked like full coverage. Now it's the highest priority gap.

---

## Testing Checklist for Agents

When writing tests for any feature, ask these questions:

### Before Writing Tests
- [ ] Have I read the REAL service implementation (not just the protocol)?
- [ ] Does this service make network calls, use hardware, or call external APIs?
- [ ] Are there any `catch {}`, `try?`, or `guard else { return }` blocks that swallow errors?
- [ ] If the real service returned zero results, would the user see an error message?

### Test Coverage Requirements
- [ ] **Unit test**: ViewModel correctly processes mock data (plumbing)
- [ ] **Contract test**: Real parser handles real/recorded response data (parsing)
- [ ] **Integration test**: Real service can produce output with controlled inputs (functionality)
- [ ] **Error path test**: When service fails, user sees a meaningful error (not blank screen)

### After Writing Tests
- [ ] Would these tests still pass if the real service was completely broken?
- [ ] If YES → you have a mock-only gap. Add an integration or contract test.
- [ ] If NO → good, your tests actually verify functionality.

---

## Key Takeaway

> **A passing mock test proves the plumbing works. It does NOT prove the feature works.**
>
> Always ask: "If I delete the mock and use the real service, would this test still pass?"
> If the answer is "no" or "I don't know," you need an integration or contract test.

Mock tests are necessary but insufficient. They're the foundation, not the whole building. The tests that catch real bugs are the ones that exercise real code with real (or recorded) data.
