# Agent Guidelines

## Build, Lint, & Test
- **Build:** `make build` or `swift build`
- **Test:** `make test` or `swift test`
- **Bundle:** `make bundle` (Required for testing entitlements/sandbox)
- **Lint:** `make lint` (SwiftLint runs automatically on build)
- **Format:** `make format` (Auto-format code)
- **Format Check:** `make format-check` (Verify formatting without changes)
- **Docs:** `make docs` (Generate Swift-DocC documentation)


## Code Style & Conventions
- **Language:** Swift & SwiftUI (macOS 15+).
- **Concurrency:** `async`/`await` exclusively.
- **Naming:** PascalCase types, camelCase vars.
- **Error Handling:** `do-try-catch` (no force unwraps).

## Git Workflow
- **Commit Messages:** Follow [Conventional Commits](https://www.conventionalcommits.org/).
  - Format: `<type>[optional scope]: <description>`
  - Types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert`.
  - Example: `feat(audio): add noise cancellation`

## Architectural Context
- **Source of Truth:** Adhere strictly to `docs/architecture-specification.md`.
- **Reproducibility:** Follow `docs/reproducibility.md`.

## Issue Tracking (Beads)
- **Create Issue:** `bd create "Title" -d "Description"` (Note: use `-d`, not `--body`)
- **List Issues:** `bd list`
- **Update Status:** `bd update <ID> --status <status>`
- **View Details:** `bd show <ID>`

## Landing the Plane
When finishing a session, follow this protocol to ensure the issue tracker remains the source of truth:

1.  **File/Update Issues**:
    *   Create new issues for any discovered bugs or remaining TODOs.
    *   Update status of in-progress issues.
    *   Close completed issues.
2.  **Quality Gates**:
    *   Ensure `make build` and `make test` pass if code was changed.
3.  **Sync Issues**:
    *   Run `bd list` to verify state.
    *   Ensure no uncommitted changes in `.beads` (unless they are local db files which are ignored).
4.  **Verify Clean State**:
    *   `git status` should be clean.

