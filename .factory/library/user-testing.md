# User Testing

Testing surface: tools, URLs, setup steps, isolation notes, known quirks.

**What belongs here:** How to test the heatmap feature manually, testing tools, surfaces, known limitations.

---

## Testing Tools
- **macOS app**: Build locally with `xcodebuild -scheme NetMonitor-macOS`, launch from build dir or Xcode
- **iOS simulator**: Build with `xcodebuild -scheme NetMonitor-iOS -destination 'platform=iOS Simulator,OS=latest,name=iPhone 17 Pro'`
- **Unit tests**: Run via SSH on mac-mini (see services.yaml commands)

## Testing Surfaces

### macOS Heatmap
- Launch app → sidebar → Heatmap
- Import floor plan (any PNG/JPEG/PDF/HEIC image works as test floor plan)
- Click on canvas to place measurement points
- Verify heatmap overlay appears after 3+ points
- Test visualization type switching in toolbar dropdown
- Test save/load via File menu
- Test PDF export

### iOS Heatmap
- Launch in simulator → Tools tab → Wi-Fi Heatmap card
- Create new project → import floor plan from photo library
- Tap canvas to place measurement points
- Verify floating HUD and heatmap overlay

### AR Features (Phase 2/3) — SIMULATOR LIMITATIONS
- AR camera feed does NOT work in simulator
- ARKit world tracking does NOT function in simulator
- These features can only be fully tested on physical device
- For simulator: verify views load without crash, verify data model/serialization paths
- Unit tests are the primary verification method for AR pipeline logic

## Flow Validator Guidance: Foundation Unit Tests

The foundation milestone has no UI surface — all assertions are verified through:
1. **Unit tests** — Run via `cd Packages/NetMonitorCore && swift test --no-parallel`
2. **Build verification** — `xcodebuild -scheme NetMonitor-macOS -configuration Debug build` and same for iOS
3. **Structural inspection** — File system checks, grep for clean slate, project.yml inspection

**Isolation:** No isolation needed — all tests are deterministic, read-only, and independent. No shared mutable state, no network, no accounts.

**Test mapping:** Each VAL-FOUND assertion maps to specific test functions in:
- `HeatmapModelsTests.swift` — serialization round-trips (VAL-FOUND-001 to -014, -047, -049, -050)
- `HeatmapRendererTests.swift` — IDW, color mapping, performance (VAL-FOUND-015 to -030, -045, -046, -051)
- `WiFiMeasurementEngineTests.swift` — engine actor tests (VAL-FOUND-031 to -035)
- `SurveyFileManagerTests.swift` — bundle format tests (VAL-FOUND-036 to -042)

**Build assertions (VAL-FOUND-013, -034, -050, VAL-CROSS-007, -009):** Verified by successful build under `SWIFT_STRICT_CONCURRENCY: complete`.

**Clean slate (VAL-FOUND-044, VAL-CROSS-010):** Verified by grep for stale heatmap references outside new directories.

## Known Limitations
- iOS NEHotspotNetwork requires precise location permission + Wi-Fi connection — returns nil in simulator
- macOS CoreWLAN requires actual Wi-Fi hardware — works on mac-mini but values may vary
- AR features require physical device with camera/LiDAR
- Speed test (active scan) requires network access — mock for unit tests

## Test Floor Plan Images
- Use any PNG/JPEG image as a test floor plan (e.g., a simple rectangle drawing)
- For calibration testing: use an image with known dimensions
