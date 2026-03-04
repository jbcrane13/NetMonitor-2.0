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

## Flow Validator Guidance: macOS Heatmap (phase1-macos)

This milestone tests the macOS heatmap feature through **code review + build verification + limited AppleScript automation**.

### Testing Approach
- **Primary: Code review** — Read the source files and verify the implementation matches each assertion's requirements.
- **Secondary: Build verification** — The macOS app builds successfully under `SWIFT_STRICT_CONCURRENCY: complete`.
- **Tertiary: AppleScript** — The app is running (PID confirmed). Use `osascript` to verify UI elements via System Events accessibility.

### App State
- The macOS app (NetMonitor-macOS) is running on this machine with a GUI session.
- Sidebar has 8 rows: [header], blakes-iphone-2.local (device), Network 192.168.3.0/24, Iphone, [separator], HEATMAP, TOOLS, SETTINGS.
- Navigate to Heatmap by selecting row 6: `osascript -e 'tell application "System Events" to tell process "NetMonitor-macOS" to tell outline 1 of scroll area 1 of group 1 of splitter group 1 of group 1 of window 1 to select row 6'`
- The Heatmap view shows empty state with "Start a WiFi Survey" text and Import/New Project/Open Project buttons.

### Key Source Files
| File | Contents |
|------|----------|
| `NetMonitor-macOS/Views/Heatmap/HeatmapSurveyView.swift` | Main survey view, toolbar, empty state, keyboard shortcuts |
| `NetMonitor-macOS/Views/Heatmap/HeatmapCanvasView.swift` | Canvas with zoom/pan, measurement dots, coverage circles, heatmap overlay |
| `NetMonitor-macOS/Views/Heatmap/MeasurementSidebarView.swift` | Right sidebar: summary stats + point list |
| `NetMonitor-macOS/Views/Heatmap/CalibrationSheet.swift` | Two-point scale calibration modal |
| `NetMonitor-macOS/Views/Heatmap/MeasurementDetailPopover.swift` | Point inspection popover |
| `NetMonitor-macOS/Views/Heatmap/DrawFloorPlanView.swift` | Draw floor plan tool |
| `NetMonitor-macOS/Views/Heatmap/HeatmapProjectListView.swift` | Entry point wrapping HeatmapSurveyView |
| `NetMonitor-macOS/ViewModels/HeatmapSurveyViewModel.swift` | ViewModel (955 lines) — all business logic |
| `Packages/NetMonitorCore/Sources/NetMonitorCore/Services/Heatmap/HeatmapRenderer.swift` | IDW interpolation + color mapping |
| `Packages/NetMonitorCore/Sources/NetMonitorCore/Services/Heatmap/SurveyFileManager.swift` | .netmonsurvey bundle save/load |
| `Packages/NetMonitorCore/Sources/NetMonitorCore/Services/Heatmap/FloorPlanImporter.swift` | Floor plan import (NSOpenPanel, format support) |
| `Packages/NetMonitorCore/Sources/NetMonitorCore/Models/Heatmap/` | All shared model types |

### Sidebar Navigation (VAL-MAC-001)
The sidebar item is in the macOS app's NavigationSection enum. Check `NetMonitor-macOS/` for the NavigationSection or sidebar configuration. The Heatmap row is confirmed present at row 6 via AppleScript.

### Isolation Rules
- Flow validators access the same running app — avoid conflicting actions.
- All code review work is read-only and safe to parallelize.
- Do NOT modify source code, build products, or app state.
- Each flow writes its report to a separate `.json` file.

### Assertion Evidence Standards
For each assertion, provide:
1. **status**: "pass", "fail", or "blocked"
2. **evidence**: Specific code references (file:line) or AppleScript output showing the assertion is met.
3. **notes**: Any caveats about what couldn't be fully verified.

## Known Limitations
- iOS NEHotspotNetwork requires precise location permission + Wi-Fi connection — returns nil in simulator
- macOS CoreWLAN requires actual Wi-Fi hardware — works on mac-mini but values may vary
- AR features require physical device with camera/LiDAR
- Speed test (active scan) requires network access — mock for unit tests

## Test Floor Plan Images
- Use any PNG/JPEG image as a test floor plan (e.g., a simple rectangle drawing)
- For calibration testing: use an image with known dimensions
