<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-02-18 -->

# NetMonitor-macOS/App

## Purpose
App entry point and SwiftData schema definition.

## Key Files

| File | Description |
|------|-------------|
| `NetMonitorApp.swift` | `@main` entry — configures `WindowGroup`, `MenuBarExtra`, `ModelContainer`, and environment objects |
| `SchemaV1.swift` | SwiftData schema version 1: `NetworkTarget`, `LocalDevice`, `SessionRecord`, `TargetMeasurement` |

## For AI Agents

### Working In This Directory
- `SchemaV1.swift` defines the canonical SwiftData models — coordinate with `DeviceDiscoveryCoordinator` when adding/modifying models
- Schema migrations require adding `SchemaMigrationPlan` — never change a model property type or name without a migration
- `NetMonitorApp.swift` wires all top-level services into `@Environment` — add new app-wide services here

### SwiftData Models
| Model | Purpose |
|-------|---------|
| `NetworkTarget` | A host being monitored (URL, protocol, interval) |
| `LocalDevice` | A discovered LAN device (IP, MAC, name, vendor) |
| `SessionRecord` | A historical monitoring session |
| `TargetMeasurement` | A single latency/status measurement for a target |

<!-- MANUAL: -->
