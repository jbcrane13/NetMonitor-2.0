<!-- Parent: ../../AGENTS.md -->
<!-- Generated: 2026-02-18 -->

# NetMonitorCore Sources

## Purpose
All source code for the `NetMonitorCore` package. Organized into Models, Services, and Utilities. This package defines the shared contract between the macOS and iOS app targets.

## Subdirectories

| Directory | Purpose |
|-----------|---------|
| `Models/` | Data models shared across platforms (see `Models/AGENTS.md`) |
| `Services/` | Service protocols and platform-agnostic implementations (see `Services/AGENTS.md`) |
| `Utilities/` | Shared utility functions (see `Utilities/AGENTS.md`) |

## Key Files

| File | Description |
|------|-------------|
| `NetMonitorCore.swift` | Module entry point; re-exports public types |

## For AI Agents

### Design Principles
- **No platform-specific code**: This package must compile on both macOS and iOS without `#if os()` guards in most files
- **Protocol-first**: Define capabilities as protocols; platforms provide implementations
- **Sendable everywhere**: All types crossing actor boundaries must be `Sendable`
- **Swift 6 strict concurrency**: No data races permitted

### Adding New Functionality
1. Define a protocol in `Services/ServiceProtocols.swift`
2. Add shared model types to `Models/`
3. Implement platform-agnostic portions in `Services/`
4. Implement platform-specific portions in the app targets' `Platform/` directories

<!-- MANUAL: -->
