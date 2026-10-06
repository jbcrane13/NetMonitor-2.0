---
name: swift-package-pins
description: Check NetMonitor's package and Xcode workspace pins when reviewing Swift package dependency updates or app build claims.
---

# Swift package pins in NetMonitor

The apps consume `NetMonitorCore` as a local package from the Xcode project. A dependency update in [the package lock](../../../Packages/NetMonitorCore/Package.resolved) can leave [the Xcode workspace lock](../../../NetMonitor-2.0.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved) at an older version. The checked-in [worktree setup](../../../scripts/setup-worktree.sh) resolves the workspace's pinned versions; a successful setup alone does not prove that an updated package-local pin reached either app.

When reviewing or making a Swift package upgrade:

1. Identify the changed dependency in `Packages/NetMonitorCore/Package.swift` and compare its `identity`, `version`, and `revision` in both resolved files. Treat a review comment as a lead, then verify the pins in the proposed commit.
2. If only the package lock changed, state which version standalone `NetMonitorCore` and the Xcode apps would resolve. Do not report the app upgrade as complete while the workspace pin differs.
3. Run `scripts/setup-worktree.sh` on the clean worktree before editing. For an intended app upgrade, update the workspace pin to the same verified release and check resolution from the Xcode project. The setup script refuses pre-existing lockfile edits, so do not use a rerun of it as the upgrade step. Build or test both app targets under the repository's current host and test policy when claiming app compatibility; record any unrun target separately. Preserve unrelated lockfile changes.

## Validation exercise

Compare the two `sentry-cocoa` pins before accepting a package-only bump. A fixture with package version `9.30.0` and workspace version `9.10.0` must be reported as an app-version mismatch even when standalone package resolution succeeds. On 2026-10-06, `bash scripts/setup-worktree.sh` in a clean isolated worktree resolved the Xcode project to Sentry `9.10.0`, confirming the boundary described in [PR #369's review](https://github.com/jbcrane13/NetMonitor-2.0/pull/369#discussion_r4181664025). This is skill evidence, not a build or test result for the proposed dependency upgrade.
