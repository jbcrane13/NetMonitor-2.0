# Implementation plan: #491 history (event log on both apps, macOS Timeline, health-score history, retention)

Issue #491; it supplies the history the #447 LLM summaries rely on. Revision 6 (after independent reviews r1–r5).
- Planner/orchestrator: Claude Opus 5.5, Rex session `llm-epic-447`, on mini-pro-1.
- Workers: Claude Opus 5.5 in visible Rex panes, one git worktree each, at most 2 at once (host disk and test
  lock).

## Requirements and exclusions

1. `NetworkEvent` gains `deviceID: UUID?` (`LocalDevice.id`) and `networkProfileID: UUID?` (`NetworkProfile.id`).
   Whenever a device maps to a `LocalDevice`, its name is `LocalDevice.displayName` at write time, on both
   platforms. Only unmatched devices fall back to the event's own text.
2. Event storage leaves UserDefaults and honours each platform's retention setting. The 500 cap is replaced by a
   documented safety ceiling (D3). Existing events migrate. One undecodable element no longer wipes the log.
3. macOS writes events for:
   - device first seen / went offline / came online
   - scan complete
   - connectivity change, which needs an app-scope monitor; see D8
   - gateway change
4. The macOS Timeline is reachable. Both platforms get a range picker, and day groups are sorted
   chronologically. The alphabetical sort of older groups is a current bug on both.
5. Health-score history per network on both platforms, retention-pruned and charted. **Sampled whenever the app
   computes a score, and also on a timer** (Blake, 2026-11-22):
   - macOS: an app-scope sampler every 15 min.
   - iOS: inside the existing background refresh task.
6. A macOS "since yesterday" dashboard brief on the #453 summary plumbing.

**Exclusions** (Blake, 2026-11-22). These follow-ups are filed **before S1 starts** and linked from #491:
- VPN events on both platforms: a macOS app-scope VPN watcher, and fixing iOS's dead VPN logging and its
  unreferenced view.
- iOS gateway and speed events.
- Moving `ConnectivityRecord`'s hard-coded 90-day prune onto `HistoryRetention`.
- A real XCUITest run of the macOS UI flows once mini-pro-2 is back.

No SwiftData schema change.

**Order (issue #491):** #491 starts after the three #453 PRs. Every slice is blocked on #453 PR 3 merging.
`ChangeDigestBuilder` and the iOS Timeline "Summarize" action land there.

**Closing:** S6 (the last slice) carries `Closes #491`. Every other PR says `Part of #491`.

## Repository evidence and decisions

**D1. JSON files, not SwiftData.** This follows the `MacSpeedTestHistory` precedent. macOS is on SchemaV3 and a
V4 needs a migration stage; iOS has no migration plan.

**D2. Event storage contract (fixed here, not left to the worker).**
- `NetworkEventService` keeps its name, protocol and `shared`. `shared` is backed by a `NetworkEventStore`
  writing `Application Support/NetMonitor/network-events.json`, a JSON array of elements.
- **`NetworkEventService()` stays in-memory.** The file-backed initializer takes an injected file URL; tests use
  temp directories only.
- **In memory:** the array is guarded by the existing lock. **Writes** are coalesced (1 s debounce) onto a
  private serial background queue, encoded off the main thread, and written atomically (`.atomic`). Explicit
  `flush()` is called:
  - iOS: on `scenePhase` going to `.background`
  - macOS: on `applicationWillTerminate`
  - after `clearAll` and prune
- **Decode** goes element by element through a lossy wrapper. Bad elements are skipped. Accepted: they are lost at
  the next rewrite, including events whose `type` an older build doesn't know. An unknown type is logged once at
  debug level.
- **Migration:** on first load with no file, read the legacy UserDefaults blob (`com.netmonitor.networkEvents`)
  lossily, write the file, and `flush()` synchronously. **Keep the legacy key unchanged for one release**, so
  downgrading to an older TestFlight build still sees the old events. A later issue removes it. If the file write
  fails, the next launch retries.
- **Isolation (tests and evidence runs never touch Blake's data):** `shared` uses a per-process temp directory
  when any of these hold: the `XCTestConfigurationFilePath` environment variable is set (unit-test host),
  `--uitesting`, or `--in-memory-store`. Both apps accept `--reset-history-files`, which deletes the event and
  health files before load. iOS `--uitesting-reset` implies it. The test host and the TestFlight app share a
  bundle ID and data store (memory `reference_release_visual_evidence`).
  - **Directory:** under `--uitesting` the directory is fixed per app (`<tmp>/netmonitor-uitest-history/`). It
    survives relaunch and is cleared only by `--reset-history-files`. The unit-test host uses a per-process temp
    directory.
- `removeEvents(olderThan:)` moves onto `NetworkEventServiceProtocol`. `log` gains `deviceID:` and
  `networkProfileID:` parameters defaulting to nil.

**D3. Ceiling.** Newest 20,000 events.
- On macOS "Forever" this caps history. The Settings retention footnote on both platforms says
  "Event history keeps up to the newest 20,000 events."
- Health samples get the same ceiling.
- The Timeline must stay smooth at 20k rows (`List`/`LazyVStack`). S3 checks a seeded 20k load.

**D4. Retention.** Pruning already exists:
- macOS: `MonitoringSession.pruneOldMeasurements(eventService:now:)` prunes events via `HistoryRetention`; it runs
  at launch and hourly while monitoring.
- iOS: `DataMaintenanceService.pruneExpiredData` (`dataRetentionDays`).

S1 only switches these calls to the protocol method. S5 adds health pruning on the same two paths after S1 merges.

**D5. macOS Timeline entry.** A Tools card `NetworkTool.timeline` (`tools_card_timeline`), defined in
`NetMonitor-macOS/Views/ToolsView.swift:44`, with routing in the `switch tool` at `ContentView.swift:181`.
- Accessibility IDs: `screen_networkTimeline`, `timeline_list_events`, `timeline_event_<uuid>`,
  `timeline_label_empty`, `timeline_picker_eventType`, `timeline_picker_range`. iOS uses the same
  `timeline_picker_range`.
- No change to Core `NavigationSection` (a sidebar entry stays an open question for Blake).

**D6. Range presets:** Today, 7 days, 30 days, All (the default).
- "Today" is the calendar day in an injected `Calendar`/`TimeZone`, with a DST-safe start of day.
- Backed by `events(from:to:)`.

**D7. macOS `MacEventRecorder`** (`NetMonitor-macOS/Platform/MacEventRecorder.swift`) is the one place that
writes macOS events. It is wired in `NetMonitorApp` next to `MacAlertDispatcher`. Mapping:
- `DeviceChangeEvent.firstSeen` → `.deviceJoined`; `.wentOffline` → `.deviceLeft`; `.cameOnline` →
  `.deviceJoined` with the title "came back online"; `.changed` is not logged. No new `NetworkEventType` cases,
  so older builds still decode.
- Rows and names come from the dispatcher (`MacRuleAlerts.row` → `displayName`).
- **Route (option A):** `DeviceDiscoveryCoordinator.onDeviceChanges` becomes a fan-out (`addDeviceChangeHandler`)
  so the dispatcher and the recorder subscribe independently. Name lookup moves into a shared helper both use.
  Under `--uitesting` the recorder subscribes even though no dispatcher exists, so UI-test scans produce device
  events. It is attached after the UI-test coordinator is built (about `NetMonitorApp.swift:178`) and before that
  branch's `return` (about line 184).
- **macOS UI-test isolation:** under `--uitesting`, the coordinator gets
  - a fixture `pipelineFactory` (existing seam) that returns two fixed devices, one with hostname
    `uitest-printer`, with no LAN scan;
  - a `DeviceChangeTracker` on an isolated `UserDefaults` suite (`netmonitor.uitest`), cleared by
    `--reset-history-files`.
  This keeps runs off Blake's real registry and network.
  - **Baseline:** the detector treats the first confirmed scan of a scope as the baseline and reports nothing new.
    The UI-test flow therefore launches with `--seed-test-device`, whose row on the active profile seeds a
    confirmed baseline. The `uitest-printer` fixture is then reported as `firstSeen`.
  - A coordinator or recorder unit test starts from an empty tracker plus that seed and expects exactly one
    `firstSeen`, for the printer.
- **Flap guard (rate limit, no buffering):** at most one `deviceLeft` and one `deviceJoined` per device per
  10 minutes. Later same-direction events inside the window are dropped. Events are written immediately with their
  real timestamp; nothing is held back.
  - **Trailing correction:** when a device's window ends, if its current state differs from the last written
    direction, write one event for the current state. A suppressed final "left" is therefore still recorded.
  - Tests: three flaps in 10 minutes give exactly one left and one joined, then a trailing write if the final
    state differs; the left → joined → left case ends with "left".
  - **Clock seam:** the window check is a scheduled task created by an injected scheduler and clock, so tests
    advance time instead of sleeping. A correction still pending when the app quits is lost (accepted; see Risks).
- **Scan complete:** a coordinator callback `onScanCompleted(profileID:deviceCount:)`.
- **Gateway:** an event only when the profile ID is the same and the gateway IP differs from the last one seen
  for that profile in this run. The first key after launch and network switches record nothing; connectivity
  covers those.

**D8. Connectivity monitor to app scope.** `ConnectivityMonitor` moves from `NetworkDetailView.onAppear`/`onDisappear`
to app scope, owned by `NetMonitorApp` for the local profile and restarted on local-network change. This also
fixes Uptime History (ConnectivityRecord), which today only records while that view is open.
`NetworkDetailView` reads the shared monitor through the environment.

**D9. iOS IDs.**
- `AppEnvironment` (`NetMonitor-iOS/App/AppEnvironment.swift`) gets a `currentNetworkProfileID` provider:
  `NetworkProfileManager.localProfile?.id ?? activeProfile?.id`.
- `EventListenerService` depends on `any DeviceDiscoveryServiceProtocol`, not the concrete shared instance.
  Under `UITEST_FAKE_DEVICES`, `AppEnvironment` gives the dashboard and the listener **the same fake discovery
  service**. Its `scanNetwork` flips `isScanning` true → false and publishes the fixture devices with the UI-test
  network's profile ID, so UI tests never scan the real network.
  - **The UI-test network** is a constant, `UITestBootstrap.networkProfileID` (a fixed UUID). Under
    `UITEST_FAKE_DEVICES`, the `currentNetworkProfileID` provider returns it, the fake service stamps it on the
    fixture devices, and seeds put it on `LocalDevice` rows. The lookup is scoped by **the provider's ID**.
  - **The fake service** is `@Observable`. `scanNetwork` sets `isScanning = true`, sleeps 300 ms, then publishes
    the devices and sets `isScanning = false`, so the listener's observation loop sees both states. A unit test
    runs a fake scan through `EventListenerService` and expects Joined and Scan Complete events.
- `EventListenerService` takes the provider and a **read-only, network-scoped device lookup**. The lookup
  matches against that network's `LocalDevice` rows only, using `DeviceMatcher` with the MAC when present, then the
  IP, and never inserts a row. It sets `networkProfileID` on every event, and `deviceID` plus `displayName` on
  joined/left when the device matches.
- `NetworkHealthScoreViewModel` uses the same provider for samples. The instance that actually runs is built at
  `DashboardView.swift:9` and shown by `RefinedNetworkHealthCard` in `DashboardView.swift` (lines 115–142).
  `Views/Dashboard/NetworkHealthScoreView.swift` is used only by its preview and is not touched.
- The existing free-text health `.toolRun` event (`NetworkHealthScoreViewModel.swift:153`) is **removed**, because
  the health history replaces it. S5 owns this.

**D10. Health samples.** `HealthScoreSample(id, networkProfileID, timestamp, score, grade)` lives in Core
`HealthScoreHistoryStore`, using the same JSON-file contract as D2 with its own file.
- `record` is throttled to one sample per network per 15 minutes.
- Sampling, both timers using the same `NetworkHealthScoreService` inputs as each platform's view model:
  - **iOS:** when `NetworkHealthScoreViewModel.performRefresh` computes a score, and in
    `BackgroundTaskService`'s refresh task. The score computation (ping 8.8.8.8 ×5 →
    `NetworkHealthScoreService`) is extracted into one iOS `HealthSampleProbe`, used by both the view model and
    the background task. The background task builds its own profile ID:
    `NetworkProfileManager().localProfile?.id`, or no sample if nil. The new background code goes in an extension
    in a new file, because `BackgroundTaskService.swift` is over the lint length. It calls
    `HealthScoreHistoryStore.flush()` before `task.setTaskCompleted`, and a unit test covers this.
  - **macOS:** when `NetworkHealthScoreMacViewModel.refresh` computes a score (it backs the real
    `Views/Dashboard/HealthGaugeCard.swift`), and in a new app-scope `MacHealthSampler` running every 15 minutes.
- **Chart:** Swift Charts line of the current network's samples over the retention window.
  - macOS: inside `HealthGaugeCard.swift`.
  - iOS: in the normal layout of `RefinedNetworkHealthCard` (`DashboardView.swift`), as a compact sparkline row
    below the score. The card has no expanded state, and none is added.
  - Hidden with fewer than 2 samples.

## Deliverable slices

| Slice | Acceptance criteria | Owned files/modules | Blockers | Verification | Worker model |
| --- | --- | --- | --- | --- | --- |
| **S1 Core event store** | D2 and D3 contract. Old JSON decodes with nil IDs. Lossy decode. Migration keeps the legacy key. Debounced off-main writes with flush. `NetworkEventService()` in-memory. Protocol change compiles in every conformer and mock. iOS: flush on `scenePhase` background. macOS: flush on terminate. Settings footnote on both. | Core `Models/NetworkEvent.swift`, `Services/NetworkEventService.swift`, new `Services/NetworkEventStore.swift` + Core tests; every `NetworkEventServiceProtocol` mock in iOS/macOS tests and the macOS tests that build `NetworkEventService()`; prune call lines in `MonitoringSession.swift` and `DataMaintenanceService.swift`; the iOS scenePhase line in `NetmonitorApp.swift` and the macOS terminate hook; the two Settings footnotes; the store-isolation and `--reset-history-files` lines in both app entry points; iOS `UITestBootstrap.swift` (the legacy-blob seed) | #453 PR 3 merged | Gates G. Unit: migration from a legacy blob containing 1 corrupt element; lossy decode; debounce and flush; ceiling; temp-dir isolation. **UI (iOS):** a launch arg seeds the legacy blob (with a corrupt element); open the Timeline and see the surviving events (screenshot); on that first launch the argument `--log-test-event "Migration check"` logs one new event (not in the legacy blob); relaunch without reset or that argument; that new event and the migrated ones are still there, and the legacy key is still present (checked in a unit test, since XCUITest can't read it). | Opus |
| **S2 macOS event writers + app-scope connectivity** | D7 and D8. One event per change with `networkProfileID`; devices also carry `deviceID` and the `displayName` name. Flap and gateway rules tested. Connectivity and Uptime History record while any screen is showing. | macOS new `Platform/MacEventRecorder.swift`; hook lines in `MacAlertDispatcher.swift`, `DeviceDiscoveryCoordinator.swift` (the fan-out `addDeviceChangeHandler` and `onScanCompleted`), `ConnectivityMonitor.swift`, `NetworkChangeRescan.swift`; `NetMonitorApp.swift` (recorder + monitor wiring; under `--uitesting` the recorder subscription, fixture pipeline and isolated tracker between about lines 178 and 184; plus a `--seed-test-events` argument); `NetworkDetailView.swift` (monitor removal only); macOS tests | S1 | Gates G. Recorder unit tests per source (temp-dir store), flap collapse, gateway same-profile rule, and a monitor that survives a view change. | Opus |
| **S4 iOS writers carry IDs** | D9 for events: profile ID on all events; `deviceID` + `displayName` for matched devices, otherwise the existing text. Test: a renamed device's custom name appears in its joined/left event. | iOS `Platform/EventListenerService.swift`, `App/AppEnvironment.swift` (provider, lookup, and the shared fake discovery service under `UITEST_FAKE_DEVICES`), `UITestBootstrap.swift` (event seeds and the custom-name `LocalDevice` seed for S3), `NetmonitorApp.swift` (start the listener under `--uitesting-events`, before the UI-test early return at about line 103), tests | S1 | Gates G | Opus (same worker as S2, run sequentially) |
| **S5 Health history** | D10. Samples on compute and on both timers; pruned on both paths; chart on both dashboards; hidden below 2 samples; `.toolRun` health event removed. | Core new `Models/HealthScoreSample.swift`, `Services/HealthScoreHistoryStore.swift`; iOS `NetworkHealthScoreViewModel.swift`, new `Platform/HealthSampleProbe.swift`, `DashboardView.swift` (the `RefinedNetworkHealthCard` chart and the VM construction line only), new `Platform/BackgroundTaskService+Health.swift` and its call line, `UITestBootstrap.swift` (sample seed); macOS `Views/NetworkHealthScoreView.swift` (the VM `refresh` hook only), `Views/Dashboard/HealthGaugeCard.swift`, new `Platform/MacHealthSampler.swift` with a wiring line and a `--seed-health-samples` argument in `NetMonitorApp.swift` (rebased after S2); health prune lines on both paths | S1; S2 merged before its `NetMonitorApp.swift` line | Gates G. Unit: throttle, prune, timer sampling with an injected clock. **UI:** iOS opens the dashboard with seeded samples (5 points, plus a 1-point case) and sees the chart, or none (screenshots); macOS uses the AX procedure on the dashboard. | Opus |
| **S3 Timeline UI** | D5 and D6 on both platforms; chronological groups; the macOS Timeline reachable with the IDs; 20k-row smoothness check. `TimelineUITests` (macOS) updated to the IDs and compiling. | macOS `Views/TimelineView.swift`, `Views/ToolsView.swift` (the timeline card), `ContentView.swift` (`switch tool` case only); iOS `ViewModels/TimelineViewModel.swift`, `Views/Timeline/TimelineView.swift`; both Timeline test files | S1, S4 (seeding helpers), S2 (macOS events exist) | Gates G. Unit: ranges with an injected calendar (DST day, month and year boundaries); sort. **UI (iOS):** seeded events today and 10 days ago; pick "Today", the old one is absent, pick "All", it is present (screenshots). **End to end (iOS):** seed one `LocalDevice` with `customName` "UITest Office Printer", the fixture MAC and the UI-test profile ID; run a scan through the shared fake discovery service; open the Timeline; see "Scan Complete" and "Device Joined: UITest Office Printer" (the custom name, not the hostname) (screenshot). **macOS:** the same Today/All flow, plus a scan with the fixture pipeline that shows Scan Complete **and "Device Joined: uitest-printer"** in the Timeline, via the AX procedure (screenshots). | Opus |
| **S6 macOS dashboard brief** | A card on `NetworkDetailView` built with `ChangeDigestBuilder` over the last **rolling 24 h** of macOS events. Cached per change (newest event ID plus device counts). Never during a scan. Hidden when unavailable, failed or empty. Generated-text marker. ID `dashboard_card_changeBrief`. The window, empty and unavailable states match iOS PR 3; re-check its API when PR 3 merges. | macOS new `Views/Dashboard/ChangeBriefCard.swift` + its VM; one placement line in `NetworkDetailView.swift` (after S2 and S5); a `--uitest-insight=answer\|unavailable` argument in `NetMonitorApp.swift`, using Core stand-ins (the PR 3 / #449 Core fakes, or moved into Core) | S2, S5, #453 PR 3 | Gates G. VM unit tests with `MockInsightService`. **AX flow:** a seeded event set with the mock insight service shows the card, key points and marker (screenshot); the unavailable mock shows no card. `Closes #491`. | Opus |

## Integration order and shared-file ownership

- **Order:**
  1. #453 PR 3.
  2. S1.
  3. In parallel: one worker on S2 then S4 (two PRs), and one worker on S5. S5's `NetMonitorApp.swift` line
     rebases after S2.
  4. S3.
  5. S6.
- **`NetMonitorApp.swift` (macOS):** S2 owns it; S5 adds one line after S2 merges; S1 adds only the terminate flush.
  S1 merges first, so there is no overlap in time.
- **`NetworkDetailView.swift`:** changed in order S2 (monitor removal), then S6 (card placement).
- **`UITestBootstrap.swift` (iOS):** S1 adds the legacy-blob seed; S4 adds the event seeds and the fake-feed hook;
  S5 adds the sample seed. These merge in that order, each rebased.
- **`NetMonitorApp.swift` UI-test lines (macOS):** in merge order, S1 (isolation and reset), S2 (recorder under
  UI tests, events seed), S5 (samples seed), S6 (insight argument).
- **`DashboardView.swift` (iOS):** #453 PR 3 (brief card), then S5 (health chart).
- **Xcode project:** the xcodeproj is checked in. A slice adding an app file runs `xcodegen generate` and commits.
  On conflict, rebase and regenerate; never hand-merge.
- **Protocol rule:** `NetworkEventServiceProtocol` changes only in S1. **Before every merge, the PR is rebased on
  current main and both app test targets are built** (lesson from 2026-11-22).

**Gates G** (every PR, on the PR's final code):
- `bash scripts/setup-worktree.sh` in the worktree first.
- `scripts/pre-commit-quality` and `scripts/pre-push-quality`.
- After `xcodegen generate`, no project diff beyond the slice's own committed change.
- `swift test --no-parallel` in NetMonitorCore (and NetworkScanKit if touched).
- The macOS and iOS unit suites.
- SwiftLint and SwiftFormat with no errors in touched files, including `type_body_length`.
- Logs grepped for `Test run with`, `Restarting after unexpected` and `Fatal error`.
- **Host:** mini-pro-1, `lockf -t 7200 /tmp/nm-mini1-test.lock timeout 1200`, private DerivedData outside the tree, a
  throwaway simulator per worker. Delete caches after each run.

**macOS UI procedure (AX)** (XCUITest is blocked on mini-pro-1):
- Launch the Debug build with the UI-test launch arguments (`--in-memory-store` plus seeding, as #449 added).
- Drive it through the Accessibility API by identifier, using the AX driver the #449 worker used (memory
  `reference_release_visual_evidence`). The worker records the exact script under `scripts/ax/` in its PR.
- Take window-only screenshots (`screencapture -l <windowid>`) and attach them to the PR.
- The real XCUITest run is a follow-up issue for when mini-pro-2 returns.

**Skills and review per PR:**
- Workers use `pocock-github-workflow:pocock-tdd` for Core and view-model logic, and `pocock-github-workflow:pocock-pr`
  for the body.
- The orchestrator reviews each PR with `pocock-github-workflow:pocock-code-review` before merging.
- Review bots and the PR comment agent handle threads. No two writers push to one branch at once: workers fetch and
  rebase on the remote branch and never force-push.

## Acceptance and release tasks

- **R1 (separate issue, open until checked):** on the first TestFlight build containing S1, an existing iOS install
  keeps its events, and the legacy key is still present. Evidence is screenshots.
- **R2 (separate issue):** remove the legacy UserDefaults key one release after R1.
- No App Store submission is in scope.

## Risks and unresolved decisions

- **Debounced writes** lose up to 1 s of events on a crash. Accepted.
- **Lossy decode** drops unknown-type elements at the next rewrite on older builds. Accepted (D2).
- **20k ceiling** caps "Forever". Accepted and shown in Settings copy (D3).
- **A trailing flap correction pending at quit** is lost; the next scan corrects the state. Accepted.
- **Timer sampling** costs a few pings every 15 minutes on the Mac and per background refresh on iOS. Accepted
  (Blake chose timer sampling).
- **Open for Blake (non-blocking):** a sidebar entry for the macOS Timeline.

## Plan review

- **r1:**
  - Reviewer: Claude Opus 5.5 (`claude -p`, high effort), session 39a9dd15-a49c-4ff0-893c-73622b8ff5b5, on revision 1.
  - Verdict: changes required, 23 findings.
  - Disposition, all addressed in revision 2:
    - 1 (VPN cut): Blake approved; follow-ups filed before S1.
    - 2: blocked on #453 PR 3.
    - 3: Blake chose timer sampling.
    - 4: D8.
    - 5, 6: D9.
    - 7: D7.
    - 8: D4.
    - 9: D10 ownership.
    - 10: D2.
    - 11: D5.
    - 12: S6 criteria.
    - 13: the AX procedure plus a follow-up.
    - 14: the S3 end-to-end flow.
    - 15: the S1 UI test.
    - 16: UITestBootstrap ownership.
    - 17: the S3 and S5 assertions.
    - 18: Gates G.
    - 19: skills and review.
    - 20: keep the legacy key (R2).
    - 21: the D2 contract.
    - 22, 23: accepted and documented.
- **r2:**
  - Reviewer: Claude Opus 5.5, session 49cd8560-864d-4b1e-bb11-37319153350b, on hash b79a6cc1a100.
  - Verdict: changes required, 7 findings.
  - Disposition, addressed in revision 3:
    - 1: the iOS chart is in `RefinedNetworkHealthCard`, with the VM construction line owned by S5.
    - 2: S4 owns starting the listener under UI tests and the fake-feed hook.
    - 3: named UI-test seams per slice, and the table corrected.
    - 4: D2 isolation plus `--reset-history-files`.
    - 5: D9 network-scoped `DeviceMatcher` lookup.
    - 6: D10 `HealthSampleProbe` plus the background profile ID.
    - 7: D7 rate limit, no buffering.
- **r3:**
  - Reviewer: Claude Opus 5.5, session cb3d581c-9716-4a68-9c72-2698f23ae701, on hash 6a42f49f63c1.
  - Verdict: changes required, 2 blocking and 3 important findings.
  - Disposition, addressed in revision 4:
    - B1: a shared fake discovery service, a seeded custom-name row, and an assertion on the custom name.
    - B2: option A, a fan-out of `onDeviceChanges`.
    - I1: a fixed UI-test directory and a new-event relaunch check.
    - I2: the trailing correction.
    - I3: a flush before `setTaskCompleted`, and the chart in the normal layout.
- **r4:**
  - Reviewer: Claude Opus 5.5, session 68a55cd1-c5f1-40ba-858f-1cf2c8f5d999, on hash 5b921efef232.
  - Verdict: changes required, 2 blocking and 3 important findings.
  - Disposition, addressed in revision 5:
    - B1: `UITestBootstrap.networkProfileID`.
    - B2: the macOS fixture pipeline, an isolated tracker, and the placement corrected.
    - I1: `--log-test-event`.
    - I2: an `@Observable` fake with a 300 ms hold, plus a unit test.
    - I3: a scheduler and clock seam, with the quit-time loss accepted.
- **r5:**
  - Reviewer: Claude Opus 5.5, session ca3b30e0-ddb4-4f65-9a70-257dcc3ae077, on hash 8bc4d234fdf1.
  - Verdict: changes required, 1 blocking finding.
  - Disposition, addressed in revision 6:
    - B1 (baseline scan): `--seed-test-device` plus a unit test.
    - The legacy-key check moved to a unit test.
- **r6:**
  - Reviewer: Claude Opus 5.5, session c9fe86c9-4b94-426f-9208-c200bf99f05e, on hash 3823a94d14dc.
  - **Verdict: pass.**
  - Non-blocking notes for S2:
    - Fixture devices must differ from the `--seed-test-device` row in IP, MAC and name, with `isCached == false`.
    - Write the empty-tracker-plus-seed test at the coordinator level, so it runs the real
      `trackerSeed` → `record(seed:)` path.
