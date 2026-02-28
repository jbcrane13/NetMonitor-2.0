<!-- Parent: ../AGENTS.md -->

# .github

## Purpose
GitHub configuration directory. Contains CI/CD workflow definitions, project automation, and collaboration tooling.

## Files

| File | Purpose |
|------|---------|
| `CODEOWNERS` | Path-based ownership — auto-requests reviews when branch protection is active |
| `dependabot.yml` | Weekly automated PRs for GitHub Actions version updates and Swift packages |
| `pull_request_template.md` | Auto-populates new PRs with summary, beads issue link, and test checklist |

## Subdirectories

| Directory | Purpose |
|-----------|---------|
| `workflows/` | GitHub Actions workflow YAML files |

## Workflows

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| `lint.yml` | PR + push to main | SwiftLint errors gate, SwiftFormat gate, bare-TODO warnings, AGENTS.md validation |
| `coverage-gates.yml` | PR + push to main | Runs full test suite + enforces per-target coverage thresholds |
| `release.yml` | Push of `v*` tag | Validates, builds macOS + iOS, creates a draft GitHub Release with auto-generated notes |

## For AI Agents

### Adding a new workflow
- Use `macos-15` as the runner for any job that requires Xcode, SwiftLint, or SwiftFormat
- Use `ubuntu-latest` for jobs that only need bash, Python, or gh CLI
- All workflows use `actions/checkout@v4` and `actions/upload-artifact@v4`
- Keep `timeout-minutes` set — omitting it can cause runaway jobs

### Triggering a release
Push a semver tag to trigger `release.yml`:
```bash
git tag -a v2.0.1 -m "NetMonitor 2.0.1"
git push origin v2.0.1
```
See `.factory/skills/create-release/SKILL.md` for the full release checklist.

### Checking workflow status
```bash
gh run list --limit 10
gh run view <run-id> --log
```

### Available skills
Agent-readable runbooks live in `.factory/skills/`:
- `run-tests` — SSH to mac-mini to run test suite
- `check-coverage` — SSH to mac-mini for coverage gate results
- `create-release` — End-to-end release procedure
- `fix-lint` — Resolve SwiftLint and SwiftFormat violations

<!-- MANUAL: -->
