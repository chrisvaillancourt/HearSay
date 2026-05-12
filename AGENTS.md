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

## Landing the Plane
When finishing a session:

1.  **Quality Gates**:
    *   Ensure `make build` and `make test` pass if code was changed.
2.  **Verify Clean State**:
    *   `git status` should be clean.

