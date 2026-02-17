<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-01-29 | Updated: 2026-02-15 -->

# Components

## Purpose
Reusable SwiftUI components implementing the Liquid Glass design system.

## Key Files
| File | Description |
|------|-------------|
| `GlassButton.swift` | Styled button with variants: primary, secondary, success, danger, ghost |
| `GlassCard.swift` | Card container with glass-morphism effect (also available as `.glassCard()` modifier) |
| `MetricCard.swift` | Compact card for displaying a single metric with label and icon |
| `StatusBadge.swift` | Colored badge for connection/status indicators |
| `EmptyStateView.swift` | Placeholder for empty lists/results with icon and message |
| `ToolInputField.swift` | Styled text input for tool host/address entry with icon |
| `ToolRunButton.swift` | Execute button for network tools with loading state |
| `ToolResultRow.swift` | Single result row for tool output lists |
| `ToolStatisticsCard.swift` | Summary statistics card for tool results |
| `ToolClearButton.swift` | Shared clear/trash button for tool views |

## For AI Agents

### Working In This Directory
- Components use `Theme` constants exclusively — never hardcode colors or spacing
- All components accept accessibility identifier parameters (usually `accessibilityID`)
- Keep components generic and reusable across features
- Follow existing naming conventions: `Glass*` for design-system components, `Tool*` for tool-specific components
- Use `.foregroundStyle(Theme.Colors.*)` instead of `.foregroundColor()` (SwiftUI modern API)

### Testing Requirements
- Verify accessibility identifiers are properly passed through
- Test button disabled/loading states
- Ensure Theme.Colors reactivity (components update when accent color changes)
- Verify proper spacing using Theme.Layout constants

### Common Patterns
- Components are standalone View structs (not ViewModifiers unless explicitly a modifier)
- Accept style customization via parameters when needed
- Use `@ViewBuilder` for flexible content composition
- Default values for optional parameters (e.g., `accessibilityID` has defaults)

### Dependencies
- Theme: `../../Utilities/Theme.swift` (required for all components)
- No ViewModels or Services (components are presentation-only)

<!-- MANUAL: -->
