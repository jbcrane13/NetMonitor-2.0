<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-02-18 -->

# NetMonitor-iOS/Widget

## Purpose
WidgetKit extension providing home screen and lock screen widgets showing network status at a glance.

## Key Files

| File | Description |
|------|-------------|
| `NetmonitorWidget.swift` | Widget definition, timeline provider, and widget views for all widget families |

## For AI Agents

### Working In This Directory
- Widgets run in a separate process — no access to app singletons or `@Observable` ViewModels
- Use `AppGroup` shared `UserDefaults` or file-based storage to pass data from the app to the widget
- Widget views must be lightweight and stateless (no `async` in widget views)
- Supported families: `.systemSmall`, `.systemMedium`, `.lockScreenCircular`, `.lockScreenRectangular`
- Timeline entries refresh via `TimelineProvider` — don't poll aggressively

### Dependencies
- `WidgetKit` — timeline, widget configuration
- `SwiftUI` — widget views

<!-- MANUAL: -->
