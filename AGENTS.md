# Agent Guidelines

## Build, Lint, & Test
- **Build:** `make build` or `swift build`
- **Test:** `make test` or `swift test`
- **Bundle:** `make bundle` (Required for testing entitlements/sandbox)
- **Lint:** Follow standard Swift conventions.

## Code Style & Conventions
- **Language:** Swift & SwiftUI (macOS 15+).
- **Concurrency:** `async`/`await` exclusively.
- **Naming:** PascalCase types, camelCase vars.
- **Error Handling:** `do-try-catch` (no force unwraps).

## Architectural Context
- **Source of Truth:** Adhere strictly to `docs/architecture-specification.md`.
- **Reproducibility:** Follow `docs/reproducibility.md`.
