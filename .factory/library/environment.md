# Environment

Environment variables, external dependencies, and setup notes.

**What belongs here:** Required env vars, external API keys/services, dependency quirks, platform-specific notes.
**What does NOT belong here:** Service ports/commands (use `.factory/services.yaml`).

---

## Build Tools
- **Xcode**: Latest (Swift 6.2.3)
- **XcodeGen**: 2.44.1 — regenerates .xcodeproj from project.yml
- **SwiftLint**: 0.63.2 — errors block commits
- **SwiftFormat**: 0.59.1 — must be clean

## Platform Requirements
- **macOS deployment**: 15.0+
- **iOS deployment**: 18.0+
- **Swift**: 6.0 with `SWIFT_STRICT_CONCURRENCY: complete`

## Test Execution
- Tests MUST run on mac-mini via SSH (never locally — no display session)
- `ssh mac-mini` connects to secondary build node
- Code must be pushed to git before running remote tests (mac-mini pulls from remote)
- xcodegen is NOT installed on mac-mini — regenerate locally before pushing

## Frameworks (Heatmap Feature)
- **CoreWLAN** (macOS): Wi-Fi RSSI, noise floor, channel, scan
- **NEHotspotNetwork** (iOS): Wi-Fi RSSI, SSID, BSSID (requires precise location + entitlement)
- **ARKit** (iOS): World tracking, mesh reconstruction, plane detection
- **RealityKit** (iOS): AR view rendering
- **Metal** (iOS): Phase 3 incremental map/heatmap rendering
- **CoreImage** (iOS): Contour detection for floor plan generation
- **CoreGraphics** (both): CGImage output for heatmap overlay
