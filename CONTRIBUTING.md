# Contributing to MeetingRecorder

Thank you for your interest in contributing to MeetingRecorder! This document provides guidelines and information to help you get started.

## Table of Contents

- [Development Environment Setup](#development-environment-setup)
- [Project Structure](#project-structure)
- [Development Workflow](#development-workflow)
- [Code Style \u0026 Standards](#code-style--standards)
- [Testing](#testing)
- [Pull Request Process](#pull-request-process)
- [Common Development Tasks](#common-development-tasks)
- [Troubleshooting](#troubleshooting)

## Development Environment Setup

### Prerequisites

- **macOS 15.0 (Sequoia)** or later
- **Xcode 16.0+** with Command Line Tools
- **Swift 6.0+** (included with Xcode)
- **Apple Silicon Mac** (M1/M2/M3) recommended for optimal performance

### Initial Setup

1. **Clone the repository**:
   ```bash
   git clone https://github.com/chrisvaillancourt/meeting-transcription.git
   cd meeting-transcription
   ```

2. **Bootstrap the project** (resolves dependencies and verifies environment):
   ```bash
   make bootstrap
   ```

3. **Verify your setup**:
   ```bash
   make build
   make test
   ```

### System Permissions

During development, you'll need to grant the following permissions to Xcode or the built app:

- **Screen Recording Permission** - System Settings → Privacy & Security → Screen Recording
- **Microphone Permission** - System Settings → Privacy & Security → Microphone  
- **Camera Permission** - System Settings → Privacy & Security → Camera

> **Tip**: If you encounter permission errors, check System Settings and ensure the app is listed and enabled.

## Project Structure

```
meeting-transcription/
├── Sources/MeetingRecorder/       # Main application source code
│   ├── MeetingRecorderApp.swift   # App entry point
│   ├── Models/                    # SwiftData models
│   │   └── MeetingModels.swift    # MeetingSession, TranscriptSegment
│   ├── Services/                  # Core business logic
│   │   ├── CaptureService.swift   # Audio/video capture orchestration
│   │   ├── AudioProcessor.swift   # Audio mixing and buffering
│   │   ├── AudioUtils.swift       # Audio format conversion utilities
│   │   ├── TranscriptionService.swift  # WhisperKit integration
│   │   └── PermissionsService.swift    # System permission management
│   └── Views/                     # SwiftUI views
│       ├── ContentView.swift      # Main app view
│       ├── RecordingView.swift    # Recording controls
│       └── SessionListView.swift  # Transcript list view
├── Tests/MeetingRecorderTests/    # Unit and integration tests
├── docs/                          # Documentation
│   ├── architecture-specification.md  # Detailed architecture
│   ├── reproducibility.md         # Build reproducibility guide
│   ├── api-reference.md           # API documentation
│   └── troubleshooting.md         # Common issues and solutions
├── Package.swift                  # Swift Package Manager manifest
├── Makefile                       # Build automation
├── .swiftlint.yml                 # SwiftLint configuration
├── .swift-format                  # swift-format configuration
└── MeetingRecorder.entitlements   # macOS app entitlements

```

### Key Components

- **CaptureService**: Orchestrates audio/video capture from ScreenCaptureKit (system audio/screen) and AVFoundation (mic/webcam)
- **AudioProcessor**: Handles audio mixing, buffering, and sends chunks to transcription
- **TranscriptionService**: Wraps WhisperKit for local speech-to-text
- **PermissionsService**: Manages system permission requests
- **SwiftData Models**: Persistent storage for meeting sessions and transcript segments

## Development Workflow

### Build Commands

All build tasks are managed through the `Makefile`:

```bash
make bootstrap      # Check environment and fetch dependencies
make build          # Build release binary (arm64)
make test           # Run test suite
make bundle         # Create .app bundle with code signing
make run            # Build, bundle, and launch the app
make lint           # Run SwiftLint manually
make format         # Auto-format code with swift-format
make format-check   # Verify formatting without making changes
make docs           # Generate Swift-DocC documentation
make clean          # Remove all build artifacts
make ci             # Run the same checks as CI (bootstrap + build + test)
```

### Running the App

For local development, use:

```bash
make run
```

This creates a properly signed `.app` bundle with entitlements, which is required for ScreenCaptureKit and other system features to work correctly.

## Code Style & Standards

### Swift Style Guide

- **Swift Version**: Swift 6.0 with strict concurrency enabled
- **Concurrency**: Use `async`/`await` exclusively; avoid completion handlers
- **Naming Conventions**:
  - `PascalCase` for types (classes, structs, enums, protocols)
  - `camelCase` for variables, functions, and properties
  - Descriptive names that clearly indicate purpose
- **Error Handling**: Use `do-try-catch`; **no force unwraps** (`!`) or force try (`try!`)
- **Access Control**: Use `private`, `fileprivate`, and `internal` appropriately; minimize public surface area

### SwiftLint

SwiftLint runs automatically during builds via a build plugin. Key rules:

- No force unwrapping or force try
- Line length limit: 120 characters
- File length limit: 400 lines
- Function length limit: 40 lines
- Cyclomatic complexity limit: 10

Configuration: [`.swiftlint.yml`](/.swiftlint.yml)

To run manually:
```bash
make lint
```

### swift-format

We use Apple's official `swift-format` for consistent code formatting:

- Indent: 4 spaces
- Maximum line length: 120 characters
- Multiline arguments/parameters formatted for readability

Configuration: [`.swift-format`](/.swift-format)

To auto-format your code:
```bash
make format
```

To check formatting without changes:
```bash
make format-check
```

### Commit Message Convention

We follow [Conventional Commits](https://www.conventionalcommits.org/):

**Format**: `<type>[optional scope]: <description>`

**Types**:
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `style`: Code style changes (formatting, no logic change)
- `refactor`: Code restructuring without behavior change
- `perf`: Performance improvements
- `test`: Adding or updating tests
- `build`: Build system or dependency changes
- `ci`: CI/CD configuration changes
- `chore`: Other changes that don't modify src or test files
- `revert`: Revert a previous commit

**Examples**:
```
feat(audio): add noise cancellation to microphone input
fix(capture): resolve timestamp sync issue between audio sources
docs(readme): add installation instructions for Apple Silicon
refactor(transcription): simplify WhisperKit initialization
test(audio): add unit tests for AudioUtils conversion
```

## Testing

### Running Tests

```bash
make test
```

### Test Organization

- Unit tests for utilities and isolated logic (e.g., `AudioUtils`)
- Integration tests for service interactions
- Tests should be deterministic and fast

### Writing Tests

- Use `XCTest` framework
- Follow AAA pattern (Arrange, Act, Assert)
- Use descriptive test names: `test_functionName_condition_expectedResult`
- Mock external dependencies when appropriate

Example:
```swift
func test_audioConversion_validSampleBuffer_returnsAVAudioPCMBuffer() throws {
    // Arrange
    let sampleBuffer = createTestSampleBuffer()
    
    // Act
    let result = AudioUtils.convert(sampleBuffer: sampleBuffer)
    
    // Assert
    XCTAssertNotNil(result)
    XCTAssertEqual(result?.format.sampleRate, 16000.0)
}
```

## Pull Request Process

### Before Submitting

1. **Create a feature branch**:
   ```bash
   git checkout -b feat/your-feature-name
   ```

2. **Make your changes** following code style guidelines

3. **Run quality checks**:
   ```bash
   make format        # Auto-format code
   make lint          # Check for lint issues
   make test          # Run tests
   make build         # Verify build succeeds
   ```

4. **Commit with conventional commit messages**:
   ```bash
   git commit -m "feat(scope): add new feature"
   ```

### Submitting a Pull Request

1. **Push your branch**:
   ```bash
   git push origin feat/your-feature-name
   ```

2. **Open a Pull Request** on GitHub with:
   - Clear title following conventional commit format
   - Description of what changed and why
   - Reference to related issues (if any)
   - Screenshots/videos for UI changes (if applicable)

3. **Respond to feedback**: Address code review comments promptly

### CI/CD Requirements

All pull requests must pass:
- ✅ Build succeeds on macOS 15 with Xcode 16
- ✅ All tests pass
- ✅ SwiftLint validation
- ✅ swift-format validation
- ✅ No compiler warnings

## Common Development Tasks

### Adding a New Audio Source

1. Extend `AudioSource` enum in `AudioProcessor.swift`
2. Update `AudioProcessor.process()` to handle the new source
3. Modify `CaptureService` to capture from the new source
4. Add tests for the new source

### Extending Transcription Capabilities

1. Review `TranscriptionService.swift` and WhisperKit documentation
2. Modify initialization or configuration as needed
3. Update `AudioProcessor` buffer handling if required
4. Add tests for new transcription features

### Adding UI Components

1. Create new SwiftUI view in `Sources/MeetingRecorder/Views/`
2. Follow existing patterns from `RecordingView.swift` and `SessionListView.swift`
3. Use `@ObservedObject` for service state (e.g., `CaptureService`)
4. Ensure UI updates happen on `@MainActor`

### Modifying Data Models

1. Update SwiftData models in `MeetingModels.swift`
2. Add migration logic if changing existing models
3. Update related services that use the models
4. Add tests for model changes

## Troubleshooting

### Build Issues

**Error: "No such module 'WhisperKit'"**
- Run `make bootstrap` to resolve dependencies
- Clean and rebuild: `make clean && make build`

**Code signing failures**
- Ensure you have a valid development certificate
- Check that `MeetingRecorder.entitlements` is correctly configured

### Permission Errors

**"Screen Recording permission denied"**
- Go to System Settings → Privacy & Security → Screen Recording
- Add Xcode or your built app and enable it
- Restart the app

**"Microphone permission denied"**
- Go to System Settings → Privacy & Security → Microphone
- Add and enable the app
- Restart the app

### Runtime Issues

**No system audio captured**
- Verify Screen Recording permission is granted
- Check that SCStream configuration has `capturesAudio = true`
- Ensure the app is excluded from capture (check `startScreenCapture()`)

**Audio/video sync issues**
- Review timestamp alignment logic in `CaptureService`
- Check that both streams are using compatible clock sources

### Getting Help

- Review [Architecture Specification](docs/architecture-specification.md) for design context
- Check [Troubleshooting Guide](docs/troubleshooting.md) for common issues
- Search existing GitHub issues
- Open a new issue with detailed description, logs, and reproduction steps

## Additional Resources

- **[Architecture Specification](docs/architecture-specification.md)** - Detailed technical design
- **[Reproducibility Guide](docs/reproducibility.md)** - Build environment details
- **[API Reference](docs/api-reference.md)** - Code documentation
- **[AGENTS.md](AGENTS.md)** - Workflow guide for AI assistants

---

**Thank you for contributing to MeetingRecorder!** 🎉
