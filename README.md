# MeetingRecorder

A native macOS 15+ application for recording meetings with real-time transcription and speaker diarization, powered by local AI. All processing happens on-device using CoreML and WhisperKit—no external APIs, no cloud services, completely private.

## Features

- 📹 **System Audio + Microphone Capture** - Record both sides of the conversation using ScreenCaptureKit and AVFoundation
- 🎥 **Screen + Webcam Recording** - Capture your screen with picture-in-picture webcam overlay
- 🤖 **Local AI Transcription** - On-device speech-to-text using WhisperKit (CoreML-optimized Whisper models)
- 👥 **Speaker Diarization** - Channel-based speaker separation (microphone vs. system audio)
- 🔍 **Searchable Transcripts** - Full-text search across all meeting transcripts with SwiftData
- 🔒 **Privacy-First** - All AI processing happens locally on your Mac, no data leaves your device
- ⚡ **Native Performance** - Built with Swift 6.0, SwiftUI, and modern macOS frameworks

## Requirements

- **macOS 15.0 (Sequoia)** or later
- **Apple Silicon (M-series)** recommended for optimal performance
- **Xcode 16.0+** (for development)
- **Swift 6.0+** (for development)

### System Permissions

MeetingRecorder requires the following permissions:
- **Screen Recording** - To capture system audio and screen content
- **Microphone Access** - To record your voice
- **Camera Access** - To record webcam video (optional)

You'll be prompted to grant these permissions on first launch.

## Installation

### For Users

> **Note**: Pre-built releases are not yet available. Follow the build instructions below.

### For Developers

1. **Clone the repository**:
   ```bash
   git clone https://github.com/chrisvaillancourt/meeting-transcription.git
   cd meeting-transcription
   ```

2. **Install dependencies**:
   ```bash
   make bootstrap
   ```

3. **Build and run**:
   ```bash
   make run
   ```
   This will build the app, create a proper `.app` bundle, code sign it with entitlements, and launch it.

## Usage

### Starting a Recording

1. Launch MeetingRecorder
2. Grant required system permissions when prompted
3. Click **Start Recording** to begin capturing audio, video, and screen
4. The app will begin transcribing speech in real-time

### Viewing Transcripts

- Transcripts appear in the main session list
- Click on any session to view its full transcript with timestamps
- Use the search bar to find specific words or phrases across all transcripts

### Stopping a Recording

- Click **Stop Recording** when your meeting ends
- The recording and transcript are automatically saved to your library

## Architecture

MeetingRecorder uses a strictly native macOS architecture:

- **Capture Engine**: ScreenCaptureKit (system audio/screen) + AVFoundation (mic/webcam)
- **Audio Pipeline**: Software-based mixing with timestamp synchronization
- **Video Compositing**: Real-time picture-in-picture using CoreImage/Metal
- **Transcription**: WhisperKit (CoreML-optimized) with VAD (Voice Activity Detection)
- **Diarization**: Channel-based speaker separation (microphone vs. remote participants)
- **Storage**: SwiftData (transcripts) + AVAssetWriter (recordings)

For detailed architectural information, see [Architecture Specification](docs/architecture-specification.md).

## Development

### Build Commands

All build tasks are managed via `Makefile`:

```bash
make build          # Build release binary
make test           # Run test suite
make bundle         # Create .app bundle with entitlements
make run            # Build, bundle, and launch the app
make lint           # Run SwiftLint
make format         # Auto-format code with swift-format
make format-check   # Verify formatting without changes
make docs           # Generate Swift-DocC documentation
make clean          # Remove build artifacts
```

### Project Structure

```
Sources/MeetingRecorder/
├── Models/              # SwiftData models (MeetingSession, TranscriptSegment)
├── Services/            # Core services
│   ├── CaptureService.swift        # Audio/video capture orchestration
│   ├── AudioProcessor.swift        # Audio mixing and buffering
│   ├── AudioUtils.swift            # Audio format conversion
│   ├── TranscriptionService.swift  # WhisperKit integration
│   └── PermissionsService.swift    # System permissions
└── Views/               # SwiftUI views
```

### Contributing

We welcome contributions! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for:
- Development environment setup
- Code style guidelines
- Pull request process
- Testing requirements

### Code Quality

This project uses:
- **SwiftLint** - Automatic linting (runs on build)
- **swift-format** - Code formatting (Apple's official formatter)
- **Conventional Commits** - Structured commit messages
- **Swift 6.0 Concurrency** - Modern async/await patterns

## Documentation

- **[Architecture Specification](docs/architecture-specification.md)** - Detailed technical architecture and design decisions
- **[Reproducibility Guide](docs/reproducibility.md)** - Build reproducibility and environment locking
- **[AGENTS.md](AGENTS.md)** - Developer workflow guide for AI agents
- **[Troubleshooting](docs/troubleshooting.md)** - Common issues and solutions
- **[API Reference](docs/api-reference.md)** - Code documentation and examples

## Roadmap

- [ ] Pre-built app releases
- [ ] Export transcripts (TXT, SRT, VTT)
- [ ] Advanced speaker identification
- [ ] Multi-language support
- [ ] Custom Whisper model selection
- [ ] Video timeline with transcript sync

## License

[License information to be added]

## Acknowledgments

- **WhisperKit** by [Argmax](https://github.com/argmaxinc/WhisperKit) - CoreML-optimized Whisper implementation
- **OpenAI Whisper** - Original speech recognition model
- **Apple** - ScreenCaptureKit, AVFoundation, and CoreML frameworks
