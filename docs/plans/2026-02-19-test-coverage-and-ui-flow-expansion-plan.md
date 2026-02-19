---
title: "Test Coverage and UI Flow Expansion Plan"
date: 2026-02-19
status: in_progress
owners:
  - platform-ios
  - platform-macos
type: quality
---

# Test Coverage and UI Flow Expansion Plan

## 1. Objective

Build a deterministic, outcome-focused test suite across iOS + macOS so that:

1. Every user interaction flow is validated by UI tests that assert user-visible outcomes (not just element existence).
2. App and package unit tests cover critical behavior, error paths, and state transitions.
3. Coverage becomes a tracked quality signal with explicit targets and CI gating.

## 2. Current Baseline (Measured 2026-02-19)

### 2.1 App targets (xcodebuild + xccov)

- iOS total (all iOS test bundles): 4,476 / 20,884 lines (21.43%)
- iOS app binary (`NetMonitor-iOS.app`): 2,912 / 17,582 lines (16.56%)
- iOS unit tests bundle: 1,564 / 1,597 lines (97.93%)
- iOS UI test bundle during successful unit run: 0 / 1,705 lines (0%)

- macOS total (all macOS test bundles): 1,216 / 26,026 lines (4.67%)
- macOS app binary (`NetMonitor-macOS.app`): 503 / 16,239 lines (3.10%)
- macOS unit tests bundle: 704 / 704 lines (100%)
- macOS UI test bundle during successful unit run: 0 / 1,258 lines (0%)

### 2.2 Swift packages (`swift test --enable-code-coverage`)

- NetMonitorCore lines: 3,045 / 9,887 (30.80%)
- NetMonitorCore functions: 42.71%
- NetworkScanKit lines: 961 / 3,259 (29.49%)
- NetworkScanKit functions: 56.72%

### 2.3 Session verification snapshot (2026-02-19, this execution)

Commands run:

- `xcodebuild test -scheme NetMonitor-iOS -only-testing:NetMonitor-iOSUITests/InteractionFlowUITests`
- `xcodebuild test -scheme NetMonitor-iOS -only-testing:NetMonitor-iOSTests`
- `xcrun xccov view --report build/NetMonitor-iOS-interaction-full-rerun1.xcresult`
- `xcrun xccov view --report build/NetMonitor-iOS-unit-full-rerun1.xcresult`

Results:

- `InteractionFlowUITests`: 6/6 passing
- `NetMonitor-iOSTests`: 229/229 passing
- Coverage snapshot (`InteractionFlowUITests` run): `NetMonitor-iOS.app` 35.89% (6,355/17,709)
- Coverage snapshot (`NetMonitor-iOSTests` run): `NetMonitor-iOS.app` 17.54% (3,107/17,709)

Notes:

- These two percentages are run-specific, not merged overall project coverage.
- Coverage-gate scripting (Phase 5) should aggregate/merge reporting into one CI artifact.

## 3. Primary Gaps Identified

## 3.1 Test quality gap (UI)

- Many UI tests assert only `waitForExistence`.
- Many tests conditionally execute with `if element.exists { ... }`, creating false positives and silent skips.
- Multiple tests rely on live network behavior, producing flakiness and non-determinism.

## 3.2 Coverage gap (iOS app)

Low/zero coverage clusters:

- Tool views (Ping/Traceroute/DNS/WHOIS/PortScanner/SpeedTest/WoL/WebBrowser/Bonjour)
- Settings + pairing flows
- Device detail flows (`DeviceDetailView`, `DeviceDetailViewModel`)
- Tools screen interaction logic (`ToolsView`)

## 3.3 Coverage gap (macOS app)

Low/zero coverage clusters:

- Main views (Dashboard/Targets/Devices/Tools/Settings)
- Tool sheet flows
- Device detail/action flows
- Menu bar and companion pathways

## 3.4 Coverage gap (packages)

NetMonitorCore and NetworkScanKit runtime services/phases have low coverage:

- NetMonitorCore: DNS, ping, traceroute, port scanner, Bonjour, WoL, speed test services
- NetworkScanKit: ARP cache, TCP probe phase, SSDP/Bonjour/ICMP/reverse DNS phases, scan engine

## 4. Complete UI Interaction Inventory (To Cover)

## 4.1 iOS interaction flows

- App launch + default Dashboard presentation
- Tab navigation: Dashboard <-> Map <-> Tools
- Dashboard:
  - Open Settings
  - Pull-to-refresh behavior
  - Open Local Devices list from card
- Network Map:
  - Run scan
  - Sort changes
  - Open device detail from row
- Device List + Device Detail:
  - Open detail
  - Execute quick actions (Ping/Port Scan/DNS/WoL)
  - Scan ports and discover services
  - Edit notes
- Tools root:
  - Open each tool card
  - Quick actions (Set Target, Speed Test shortcut, Ping Gateway)
  - Recent activity clear
- Set Target sheet:
  - Set target, clear target, reopen and verify saved target state
  - Verify selected target pre-fills all target-based tools
- Each tool flow (Ping/Traceroute/DNS/WHOIS/Port Scanner/Bonjour/Speed Test/WoL/Web Browser):
  - Input validation and run-button enable/disable transitions
  - Start action changes running state and visible progress/results
  - Stop/cancel path
  - Clear/reset path
  - Error path surface where applicable
- Settings:
  - Every row/toggle/picker/button interaction
  - Conditional controls (e.g., high latency threshold visibility)
  - Alerts (clear history/cache) cancel + confirm paths
  - Export menu action surface
  - Acknowledgements navigation and return
  - Mac pairing entry/exit and manual connect form interactions

## 4.2 macOS interaction flows

- App launch + default dashboard detail
- Sidebar navigation to all sections
- Dashboard monitoring controls + quick actions
- Targets CRUD flow (open sheet, fill, validate, add, delete, sort, toggle enabled)
- Devices scanning/filtering/search/context menu actions
- Device detail editing and quick-action buttons
- Tools cards open/close and run/stop/clear states per tool
- Settings tabs and all interactions inside each tab
- Menu bar popover open/toggle/open-app interactions
- Companion enable/disable and port edit flow

## 5. Required Test Architecture Improvements

## 5.1 Deterministic UI Test Mode

Add explicit test mode for both apps with launch arguments/environment:

- In-memory or isolated data store for UI tests
- Deterministic UserDefaults/bootstrap values
- Disable background jobs/refresh scheduling not under test
- Disable external side effects (notifications, network-dependent warmups where possible)
- Stable seed data fixtures for devices/targets/tool history

## 5.2 UI test reliability standards

- No `if element.exists` guards for critical steps
- Every critical step uses hard assertion with timeout + failure message
- Every interaction validates a state change (before/after assertion)
- Use reusable test helpers for:
  - Launch configuration
  - Scroll-to-element
  - Clear/type text
  - Wait for disappearance

## 5.3 Unit-test scope expansion strategy

- Focus on uncovered view-model logic and coordinator/service behavior.
- Add error and cancellation paths, not only happy paths.
- Prefer protocol-based mocks for deterministic async streams.

## 6. Execution Plan (Phased)

## Phase 0: Harness Foundation

- Add iOS UI test launch bootstrap and deterministic defaults reset
- Add reusable iOS UI test base class/helpers
- Add equivalent macOS launch baseline hardening
- Add coverage extraction scripts for app + packages in one command

Acceptance criteria:

- UI tests launch in deterministic mode locally and in CI
- No test file depends on prior run state

## Phase 1: iOS High-Value Interaction Outcomes

- Replace soft/smoke checks with true outcome assertions for:
  - Tab navigation
  - Settings interactions and alerts
  - Set Target and cross-tool prefill behavior
  - Pairing open/close flow

Acceptance criteria:

- Critical iOS navigational/settings flows fully deterministic and outcome-verified
- Existing silent-skip patterns removed from touched tests

## Phase 2: iOS Tool-by-Tool Deep Interaction Coverage

For each tool, add outcome checks for:

- Input validation and enable/disable state
- Start -> in-progress UI transition
- Result/error render
- Stop/cancel
- Clear/reset
- Activity log update (where applicable)

Acceptance criteria:

- Every tool has at least one happy-path and one non-happy-path UI flow test

## Phase 3: macOS Interaction Outcome Coverage

- Convert sidebar/targets/devices/tools/settings tests from smoke to outcome-focused flows
- Cover target CRUD and device action flows end-to-end
- Cover menu bar popover action outcomes

Acceptance criteria:

- All major macOS user journeys validated with state-change assertions

## Phase 4: Unit Coverage Expansion

- iOS ViewModels: DeviceDetailViewModel, Tools/Settings edge/error cases, pairing service behaviors
- macOS services/coordinators: discovery, monitoring, companion/message handling, menu-bar orchestration
- NetMonitorCore services: protocol-constrained unit tests for DNS/ping/port/WoL/traceroute parsing and failures
- NetworkScanKit phases: deterministic phase tests with synthetic packets/hosts/timeouts

Acceptance criteria:

- Uncovered critical business logic has direct unit tests
- Error and cancellation paths are represented

## Phase 5: Coverage Gates + Reporting

- Add CI script to generate and archive:
  - xccov summaries for app targets
  - llvm-cov JSON summaries for package targets
- Enforce floor checks (initial practical targets):
  - NetMonitor-iOS.app: >= 30%
  - NetMonitor-macOS.app: >= 20%
  - NetMonitorCore: >= 40%
  - NetworkScanKit: >= 38%
- Raise thresholds incrementally each sprint

Acceptance criteria:

- CI fails when coverage falls below enforced floor
- Coverage trend is visible and documented

## 7. Bead Breakdown (Planned)

- Epic: Comprehensive test coverage expansion for NetMonitor 2.0
- Task 1: Deterministic UI-test harness and launch/bootstrap support
- Task 2: iOS core interaction outcome tests (navigation/settings/target/pairing)
- Task 3: iOS tool flow outcome tests
- Task 4: macOS interaction outcome tests
- Task 5: iOS + macOS unit test expansion for uncovered logic
- Task 6: coverage gate scripts and CI enforcement

## 8. Definition of Done

- Every documented user interaction flow has at least one UI test that verifies the expected outcome.
- No critical UI test path uses optional existence guards that can silently skip verification.
- High-risk business logic paths have unit tests for success/failure/cancellation.
- Coverage floors are enforced in CI and non-regressing.
