<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-01-29 | Updated: 2026-02-15 -->

# Views

## Purpose
SwiftUI views organized by feature area. Each subdirectory corresponds to a tab or major feature.

## Subdirectories
| Directory | Purpose |
|-----------|---------|
| `Dashboard/` | Main dashboard with network status overview (see `Dashboard/AGENTS.md`) |
| `NetworkMap/` | Device discovery and network topology view (see `NetworkMap/AGENTS.md`) |
| `Tools/` | Network tool views — ping, port scan, DNS, traceroute, etc. (see `Tools/AGENTS.md`) |
| `Components/` | Reusable UI components — cards, buttons, badges (see `Components/AGENTS.md`) |
| `Settings/` | App settings and configuration (see `Settings/AGENTS.md`) |
| `DeviceDetail/` | Device detail view for individual device information (see `DeviceDetail/AGENTS.md`) |

## For AI Agents

### Working In This Directory
- Views own their ViewModel via `@State`
- Use `@Bindable` for creating bindings to observable properties
- Use components from `Components/` for consistent styling
- Apply `Theme` constants from `Utilities/Theme.swift`
- All interactive elements need accessibility identifiers: `{screen}_{element}_{descriptor}`
- Use `GlassCard` modifier (or `.glassCard()`) and `GlassButton` for the Liquid Glass aesthetic
- Use `.themedBackground()` modifier for consistent background styling
- Navigation bars should use `.toolbarBackground(.ultraThinMaterial, for: .navigationBar)`

### Testing Requirements
- Verify all accessibility identifiers follow the naming convention
- Test Theme.Colors reactivity when accent color changes
- Ensure proper spacing using Theme.Layout constants

### Common Patterns
- Views use `@Environment(\.modelContext)` for SwiftData access
- `@Query` for reactive SwiftData fetching
- `@MainActor @Observable` classes for ViewModels
- AsyncStream for streaming results (ping, port scan)

### Dependencies
- ViewModels: `../ViewModels/`
- Services: `../Services/`
- Models: `../Models/`
- Theme: `../Utilities/Theme.swift`

<!-- MANUAL: -->
