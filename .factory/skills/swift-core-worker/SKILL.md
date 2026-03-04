---
name: swift-core-worker
description: Builds shared Swift core logic in NetMonitorCore — models, services, renderers, serialization, and unit tests.
---

# Swift Core Worker

NOTE: Startup and cleanup are handled by `worker-base`. This skill defines the WORK PROCEDURE.

## When to Use This Skill

Use for features that involve:
- Shared data models in `Packages/NetMonitorCore/`
- Service protocols in `ServiceProtocols.swift`
- Shared computation (HeatmapRenderer, IDW interpolation)
- Shared actors/services (WiFiMeasurementEngine)
- File format serialization (.netmonsurvey bundle)
- Deleting/cleaning up old code across the monorepo
- Unit tests for any of the above

## Work Procedure

### Step 1: Understand the Feature
- Read the feature description, preconditions, expectedBehavior, and verificationSteps from features.json
- Read `AGENTS.md` for coding conventions and boundaries
- Read `.factory/library/architecture.md` for package placement and patterns
- If the feature touches existing code, read the relevant files first

### Step 2: Write Tests First (TDD — Red Phase)
- Create test file(s) in `Packages/NetMonitorCore/Tests/NetMonitorCoreTests/` or `Tests/NetMonitor-macOSTests/` or `Tests/NetMonitor-iOSTests/` as appropriate
- Use Swift Testing framework (`@Suite`, `@Test`, `#expect`)
- Write tests that cover ALL expectedBehavior items from the feature
- Tests must be compilable but failing (no implementation yet)
- For models: test Codable round-trip, Equatable, Sendable conformance
- For renderer: test IDW output values, color mapping, edge cases, performance
- For services: test with mock dependencies using protocols

### Step 3: Implement (Green Phase)
- Create source files in the correct package paths (see architecture.md)
- Follow existing code style: 4-space indent, explicit `public` on API types
- All types: `Sendable`, `Codable`, `Identifiable` as appropriate
- Services: actor or Sendable protocol conformance
- Protocols: add to `ServiceProtocols.swift` following existing pattern
- Enums: add cases to existing enums in `Enums.swift` if needed

### Step 4: Verify
- Run `cd Packages/NetMonitorCore && swift build -c debug` — must succeed with zero errors
- Run `xcodebuild -scheme NetMonitor-macOS -configuration Debug build` — must succeed
- Run `xcodebuild -scheme NetMonitor-iOS -configuration Debug build` — must succeed
- Run `swiftlint lint --quiet` — zero errors in new/modified files
- Run `swiftformat .` — zero violations
- If project.yml was modified, run `xcodegen generate` first
- Run tests via SSH: `ssh mac-mini "cd ~/Projects/NetMonitor-2.0 && git pull && swift test -c debug --no-parallel --package-path Packages/NetMonitorCore 2>&1 | tail -30"`
  - If mac-mini is unreachable, run tests locally as fallback: `cd Packages/NetMonitorCore && swift test --no-parallel`

### Step 5: Update Shared State
- If you discovered architectural patterns or gotchas, update `.factory/library/architecture.md`
- If you found environment issues, update `.factory/library/environment.md`

## Example Handoff

```json
{
  "salientSummary": "Built SurveyProject, FloorPlan, MeasurementPoint, and 8 supporting model types in NetMonitorCore/Models/Heatmap/. All types are Sendable + Codable + Identifiable. Added WiFiMeasurementEngine actor in Services/Heatmap/ with passive/active/continuous measurement modes delegating to injected WiFiInfoServiceProtocol. Wrote 42 unit tests covering serialization round-trips, IDW interpolation correctness, color mapping for all 5 visualization types, and engine delegation. All tests pass, both targets build.",
  "whatWasImplemented": "Created 6 new files: HeatmapModels.swift (SurveyProject, FloorPlan, MeasurementPoint, HeatmapVisualization, SurveyMode, WiFiBand, CalibrationPoint, WallSegment, SurveyMetadata, FloorPlanOrigin), WiFiMeasurementEngine.swift (actor with passive/active/continuous modes), HeatmapRenderer.swift (IDW p=2.0, 5 color mappings, CGImage output), SurveyFileManager.swift (.netmonsurvey bundle save/load). Added HeatmapServiceProtocol to ServiceProtocols.swift. Added ToolType.wifiHeatmap to Enums.swift.",
  "whatWasLeftUndone": "",
  "verification": {
    "commandsRun": [
      {"command": "cd Packages/NetMonitorCore && swift build -c debug", "exitCode": 0, "observation": "Build succeeded, zero warnings"},
      {"command": "xcodebuild -scheme NetMonitor-macOS -configuration Debug build 2>&1 | tail -5", "exitCode": 0, "observation": "BUILD SUCCEEDED"},
      {"command": "xcodebuild -scheme NetMonitor-iOS -configuration Debug build 2>&1 | tail -5", "exitCode": 0, "observation": "BUILD SUCCEEDED"},
      {"command": "swiftlint lint --quiet 2>&1 | grep -c 'error'", "exitCode": 0, "observation": "0 errors"},
      {"command": "cd Packages/NetMonitorCore && swift test --no-parallel 2>&1 | tail -10", "exitCode": 0, "observation": "42 tests passed, 0 failures"}
    ],
    "interactiveChecks": []
  },
  "tests": {
    "added": [
      {"file": "Packages/NetMonitorCore/Tests/NetMonitorCoreTests/HeatmapModelsTests.swift", "cases": [
        {"name": "testSurveyProjectRoundTrip", "verifies": "Full SurveyProject serialization"},
        {"name": "testMeasurementPointAllFields", "verifies": "MeasurementPoint with all optional fields"},
        {"name": "testFloorPlanOriginCases", "verifies": "All FloorPlanOrigin cases round-trip"}
      ]},
      {"file": "Packages/NetMonitorCore/Tests/NetMonitorCoreTests/HeatmapRendererTests.swift", "cases": [
        {"name": "testIDWSinglePoint", "verifies": "Single point produces constant output"},
        {"name": "testIDWGradient", "verifies": "Two points produce correct gradient"},
        {"name": "testColorMappingSignalStrength", "verifies": "RSSI → green/yellow/red mapping"}
      ]}
    ]
  },
  "discoveredIssues": []
}
```

## When to Return to Orchestrator

- Feature requires UI code (Views, ViewModels) — wrong worker type
- Platform-specific service implementation needed (CoreWLAN, NEHotspotNetwork, ARKit)
- project.yml changes that affect target configuration beyond simple additions
- Existing test infrastructure is broken and cannot be fixed
- Feature depends on code that doesn't exist yet (check preconditions)
