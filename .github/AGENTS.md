<!-- Parent: ../AGENTS.md -->
<!-- Generated: 2026-02-24 -->

# .github

## Purpose
GitHub configuration directory. Contains CI/CD workflow definitions for the project.

## Subdirectories
| Directory | Purpose |
|-----------|---------|
| `workflows/` | GitHub Actions workflow YAML files |

## For AI Agents

### Working In This Directory
- All automation lives under `workflows/`. There are currently no other GitHub configuration files (no `CODEOWNERS`, no issue templates, no Dependabot config).
- When adding new workflows, use `macos-15` as the runner to match the existing environment.
- Do not create files directly in `.github/` unless they are standard GitHub-recognized configuration files.

<!-- MANUAL: -->
