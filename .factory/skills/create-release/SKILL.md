---
name: create-release
description: Cut a versioned NetMonitor-2.0 release. Creates a git tag, pushes it, which triggers the release.yml workflow to build both targets and publish a GitHub Release with auto-generated notes. Use when all P0/P1 bugs are fixed, tests pass, and the release prep checklist (NetMonitor-2.0-c0p) is complete.
---

# Create a Release — NetMonitor-2.0

## Prerequisites — complete the release prep checklist first

```bash
bd show NetMonitor-2.0-c0p    # View the release prep checklist
```

All items must be checked before tagging:
- All blocking bugs fixed and verified
- Full test suite passing (use `check-coverage` skill)
- No P0 silent failures outstanding
- Coverage meets all thresholds
- Build succeeds with release scheme
- Signing/provisioning verified
- Release notes drafted (auto-generated, but review them)

## Step 1 — Verify clean state

```bash
git status                   # Must show clean working tree
git log --oneline -5         # Confirm latest commits are as expected
swiftlint lint --quiet       # Must show 0 errors
swiftformat --lint .         # Must show 0 files need formatting
```

## Step 2 — Bump version in project.yml

Version fields to update in `project.yml`:

```yaml
# NetMonitor-macOS
CFBundleShortVersionString: "2.0"   # User-visible version (e.g. 2.0.1)
CFBundleVersion: "16"               # Build number — increment by 1 each release

# NetMonitor-iOS
CFBundleShortVersionString: "2.0"
CFBundleVersion: "2"
```

After editing `project.yml`:

```bash
xcodegen generate           # Regenerate .xcodeproj
git add project.yml NetMonitor-2.0.xcodeproj/
git commit -m "chore: bump version to 2.x.y (build N)"
git push
```

## Step 3 — Create and push the tag

```bash
# Format: v{major}.{minor}.{patch}
git tag -a v2.0.0 -m "NetMonitor 2.0.0"
git push origin v2.0.0
```

This triggers `.github/workflows/release.yml` automatically.

## Step 4 — Monitor the release workflow

```bash
gh run list --workflow=release.yml --limit 5
gh run view --log $(gh run list --workflow=release.yml --limit 1 --json databaseId --jq '.[0].databaseId')
```

## Step 5 — Review and publish the GitHub Release

The workflow creates a draft release with auto-generated notes. Review it:

```bash
gh release view v2.0.0
```

If the notes look correct, publish:

```bash
gh release edit v2.0.0 --draft=false
```

## Step 6 — Close the release prep issue

```bash
bd close NetMonitor-2.0-c0p
bd sync
git push
```

## Version convention

- `v2.0.0` — major feature release
- `v2.0.1` — bug fix release
- `v2.1.0` — minor feature addition
- Build number increments on every release regardless of semver
