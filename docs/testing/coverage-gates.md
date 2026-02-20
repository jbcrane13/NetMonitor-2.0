# Coverage Gates

Coverage gates are enforced by `scripts/coverage/collect-and-gate.sh`.

## What It Collects

- App coverage (`xccov`):
  - `NetMonitor-iOS.app`
  - `NetMonitor-macOS.app`
- Package coverage (`swift test --enable-code-coverage` + LLVM JSON):
  - `NetMonitorCore`
  - `NetworkScanKit`

## Floor Thresholds

- `NetMonitor-iOS.app`: `30%`
- `NetMonitor-macOS.app`: `20%`
- `NetMonitorCore`: `40%`
- `NetworkScanKit`: `38%`

The script exits non-zero when any target falls below its floor.

## Outputs

The script writes artifacts to `build/coverage/`:

- `coverage-summary.json`
- `coverage-summary.md`
- `NetMonitor-iOS-coverage.json`
- `NetMonitor-macOS-coverage.json`
- `NetMonitorCore-coverage.json`
- `NetworkScanKit-coverage.json`

## CI

GitHub Actions workflow: `.github/workflows/coverage-gates.yml`

- Runs on pushes to `main` and all pull requests
- Uploads coverage artifacts even when checks fail
