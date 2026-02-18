<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-02-18 -->

# NetMonitor-macOS/Utilities

## Purpose
App-level utilities and Swift extensions used across the macOS target.

## Key Files

| File | Description |
|------|-------------|
| `ContinuationTracker.swift` | Thread-safe registry for in-flight `CheckedContinuation` instances; prevents continuation leaks |
| `WindowOpener.swift` | Opens specific app windows by ID via `NSWorkspace` / `openWindow` environment action |
| `AppearanceEnvironment.swift` | `@Environment` key for injecting appearance/theme into the view hierarchy |
| `ColorExtension.swift` | `Color` and `NSColor` helpers for hex initialization and interpolation |
| `EnumExtensions.swift` | Convenience extensions on `DeviceType`, `StatusType`, and other enums (display names, icons) |
| `WakeOnLanAction.swift` | Sends Wake-on-LAN magic packets via UDP broadcast |

## For AI Agents

### Working In This Directory
- `ContinuationTracker` must be used whenever bridging a callback API to `async/await` — prevents double-resume crashes
- `EnumExtensions.swift` is the canonical place for display names and SF Symbol names for shared enums
- Do not put business logic here — utilities only

<!-- MANUAL: -->
