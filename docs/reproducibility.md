# Reproducible Build Strategy

Since Docker is not available for native macOS frameworks, we achieve reproducibility through **Environment Locking** and **Dependency Pinning**.

## 1. Dependency Locking
We use Swift Package Manager (SPM) which generates a `Package.resolved` file.
*   **Rule:** `Package.resolved` MUST be committed to git.
*   **Enforcement:** CI will fail if the `Package.resolved` is out of sync with `Package.swift`.

## 2. Environment Locking
We define the canonical build environment in `.github/workflows/ci.yml`.

| Component | Version | Constraint Mechanism |
|-----------|---------|----------------------|
| OS | macOS 15 (Sequoia) | `runs-on: macos-15` |
| Swift | 6.0 | `swift-tools-version: 6.0` |
| Xcode | 16.0+ | `DEVELOPER_DIR` in CI |
| Arch | arm64 | `Makefile` flag |

## 3. Build Commands
To ensure local builds match CI builds, strictly use the `Makefile` interface:

```bash
make bootstrap  # Fetch deps and verify environment
make build      # Build release binary
make test       # Run test suite
```

## 4. Artifact Verification
Build artifacts are located in `.build/arm64-apple-macosx/release/`.
To verify a build matches the source, run `make clean && make build` on a machine matching the Environment Locking specs.
