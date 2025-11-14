# **macOS Meeting Recorder & Transcriber: Software Engineering Specification**

**Version:** 1.0

**Date:** October 23, 2025

**Status:** WIP

## TODO's

review spec [feedback from chatGPT](https://chatgpt.com/c/68fd425a-6c48-8320-9cdf-f98bc4febd8c)

## **1.0 Introduction**

### **1.1 Purpose**

This document provides a detailed software engineering specification for a native macOS application designed to record, transcribe, and diarize meetings locally. The application will capture microphone input, system audio output, and optionally, video from the screen or webcam. All processing will occur on the user's machine to ensure data privacy.

### **1.2 Scope**

The scope of this project is to develop a fully functional desktop application for **macOS 15 and newer**. The application will focus exclusively on modern APIs, ensuring optimal performance, stability, and forward compatibility. The initial release will support transcription and diarization for the **English language only**.

### **1.3 Key Features**

* **Multi-Source Audio Capture:** Simultaneously record audio from the user's microphone and the system's audio output.
* **Optional Video Capture:** Allow the user to record a specific application window, a full display, and/or a webcam feed.
* **Multi-Track Recording:** Save all captured media streams (mic audio, system audio, video) as separate, synchronized tracks within a single container file.
* **Offline Post-Processing:** Perform all transcription and speaker diarization tasks after the recording is complete, ensuring no real-time performance overhead.
* **Accurate Transcription:** Convert spoken English audio into written text.
* **Speaker Diarization:** Identify and label distinct speakers in the final transcript ("who said what").

---

## **2.0 System Architecture**

The system is divided into two primary components: a **Real-Time Capture Engine** responsible for recording media, and an **Offline Post-Processing Pipeline** for generating the final transcript.

### **2.1 Core Technologies**

| Component | Technology | Rationale |
| :---- | :---- | :---- |
| **Application Framework** | Swift & SwiftUI | Native macOS development for optimal performance, system integration, and user experience. Swift provides safe memory management, modern concurrency (async/await), and seamless integration with Apple frameworks. SwiftUI offers declarative UI with less code than AppKit. |
| **System Audio Capture** | Core Audio Taps API | Modern, native macOS API for capturing system audio without requiring third-party kernel extensions or virtual audio devices (eliminates dependencies like BlackHole or Soundflower). Stable, secure, and officially supported by Apple since macOS 13.1 **Alternative considered:** Third-party virtual audio drivers (rejected due to kernel extension requirements and security concerns). |
| **Screen/Window Capture** | ScreenCaptureKit | State-of-the-art, high-performance framework for screen and window capture on macOS, introduced in macOS 12.3+. Provides fine-grained control over captured content (individual windows, applications, or displays) with hardware acceleration.3 **Alternative considered:** Legacy AVCaptureScreenInput (deprecated). |
| **Webcam Capture** | AVFoundation | Standard, mature Apple framework for capturing media from camera devices with extensive format support and hardware integration.5 Provides consistent API across Apple platforms. |
| **Media File Writing** | AVFoundation (AVAssetWriter) | Robust framework for writing multiple, synchronized media tracks to a single container file.7 Handles timestamp synchronization automatically and supports various codecs and container formats. **Alternative considered:** FFmpeg (rejected for recording due to complexity; still used for post-processing). |
| **Speech-to-Text (Primary)** | Apple Speech Framework | macOS 15+ introduces SpeechAnalyzer and SpeechTranscriber APIs with 2x faster performance than Whisper, automatic Neural Engine optimization, and native word-level timestamps. No model management required. |
| **Speech-to-Text (Alternative)** | Whisper (via WhisperKit) | State-of-the-art open-source model with high accuracy. WhisperKit provides a CoreML-optimized implementation for maximum performance on Apple Silicon.9 Offers transparency and auditability for users who prefer open-source solutions. |
| **Speaker Diarization** | pyannote.audio | Leading open-source toolkit for speaker diarization with strong performance and compatibility with both Apple Speech and Whisper outputs.12 Uses state-of-the-art deep learning models for accurate speaker segmentation. **Alternative considered:** Resemblyzer (less accurate for overlapping speech). |
| **Word-level Timestamps** | Native APIs / WhisperX | Apple Speech Framework provides word-level timestamps natively. For WhisperKit, use WhisperX forced-alignment technique to refine timestamps, crucial for accurately synchronizing transcription with speaker diarization results.5 |

### **2.2 Framework Alternatives Considered**

This section documents alternative technologies that were evaluated during the design phase:

#### **2.2.1 Application Framework Alternatives**

* **Objective-C:** Still supported but considered legacy for new development. Swift provides better safety, modern syntax, and is Apple's recommended language for macOS 15+.
* **Electron/Node.js:** Would enable cross-platform development but adds significant overhead (bundled Chromium) and complicates integration with macOS-specific APIs like Core Audio Taps and ScreenCaptureKit. Since we target macOS exclusively, native Swift is more efficient.
* **AppKit (Cocoa):** The traditional macOS UI toolkit. While powerful, SwiftUI provides faster development, automatic dark mode support, and declarative syntax. AppKit may still be used for specific edge cases if needed.

#### **2.2.2 Audio Capture Alternatives**

* **Third-party Virtual Audio Drivers (BlackHole, Soundflower):** Previously the only way to capture system audio. **Rejected** because:
  * Requires users to install third-party kernel extensions
  * Security concerns and user permission complexity
  * Core Audio Taps API makes these unnecessary on macOS 13+
* **AVAudioEngine Tap:** Lower-level API that could be used for processing, but Core Audio Taps provides more direct access to system audio at the source.

#### **2.2.3 Video Capture Alternatives**

* **AVCaptureScreenInput:** Deprecated by Apple. ScreenCaptureKit is the modern replacement with better performance and more features.
* **Third-party libraries (ffmpeg):** Could work but requires C bridging and doesn't integrate as seamlessly with Swift/SwiftUI as ScreenCaptureKit.

#### **2.2.4 Audio Processing Helpers**

* **AudioKit:** Swift framework that simplifies audio processing tasks. **Considered as optional dependency** for:
  * Audio format conversion
  * Real-time waveform visualization
  * Audio level monitoring
  * Not required but may simplify certain tasks; AVFoundation covers basic requirements

### **2.3 Data Flow Diagram**

#### **2.3.1 Real-Time Capture Flow**

Code snippet

graph TD
    A\[Physical Microphone\] \--\> B(Core Audio);
    C \--\> D(Core Audio Taps);
    B \--\> E{Aggregate Audio Device};
    D \--\> E;
    E \--\> F\[Capture Engine\];
    F \--\> G(De-interleave Audio);
    G \--\> H(Mic Audio Stream);
    G \--\> I(System Audio Stream);

    J \--\> K(ScreenCaptureKit);
    L \--\> M(AVFoundation);
    K \--\> N{Real-Time Compositor};
    M \--\> N;
    N \--\> O(Composited Video Stream);

    H \--\> P(AVAssetWriter);
    I \--\> P;
    O \--\> P;
    P \--\> Q();

#### **2.3.2 Post-Processing Flow**

Code snippet

graph TD
    A() \--\> B{Audio Extraction (FFmpeg)};
    B \--\> C(16kHz Mono WAV);
    C \--\> D;
    C \--\> E\[pyannote.audio Pipeline\];
    D \--\> F(Transcription with\<br\>Word-Level Timestamps);
    E \--\> G(Speaker Segments);
    F \--\> H{Alignment Algorithm};
    G \--\> H;
    H \--\> I();

---

## **3.0 Real-Time Capture Engine Specification**

The capture engine is responsible for acquiring all media streams and writing them to a file.

### **3.1 Audio Capture (Core Audio Taps)**

Since the target is macOS 15+, the implementation will exclusively use the modern Core Audio Taps API, eliminating the need for third-party virtual audio drivers.1

1. **Permissions:** The application's Info.plist must include the NSAudioCaptureUsageDescription and NSMicrophoneUsageDescription keys with user-facing strings explaining why access is required.1
2. **System Audio Tap:**
   * Create a CATapDescription to configure a tap on the system's default audio output device.
   * Use AudioHardwareCreateProcessTap to create the audio tap, which will provide the system's audio output as a stream.1
3. **Aggregate Device Creation:**
   * Programmatically create an aggregate audio device using AudioHardwareCreateAggregateDevice.1
   * This aggregate device must be configured to combine two inputs:
     1. The user's selected physical microphone.
     2. The newly created system audio tap.
4. **Data Capture and De-interleaving:**
   * The application will capture the combined multi-channel stream from the aggregate device.
   * The incoming AudioBufferList will contain interleaved channels (e.g., channels 1-2 for the microphone, channels 3-4 for the system audio).
   * The audio callback must de-interleave this data into two separate streams: one for the microphone and one for system audio. These separated streams will be written to distinct audio tracks in the output file.

### **3.2 Video Capture (ScreenCaptureKit & AVFoundation)**

Video capture is an optional feature initiated by the user.

1. **Permissions:** The Info.plist must include NSCameraUsageDescription. The system will also prompt for Screen Recording permission on first use.4
2. **Content Selection:**
   * Use SCShareableContent to get a list of all capturable windows, applications, and displays.3
   * The UI will present this list to the user for selection.
3. **Screen/Window Capture:**
   * Based on user selection, create an SCContentFilter to isolate the desired content (e.g., a single application window).3
   * Configure an SCStreamConfiguration with desired properties (resolution, frame rate).
   * Initialize an SCStream with the filter and configuration. The stream's delegate will receive video frames as CMSampleBuffer objects.4
4. **Webcam Capture (Optional):**
   * Use a standard AVCaptureSession to capture video from the user's selected webcam.5
   * The session's AVCaptureVideoDataOutput delegate will provide webcam frames as CMSampleBuffer objects.
5. **Real-Time Compositing (Picture-in-Picture):**
   * If both screen and webcam recording are enabled, the two video streams must be composited in real-time into a single stream.
   * Use AVMutableVideoComposition to create a composition that layers the scaled-down webcam frame on top of the screen capture frame for each timestamp.10 The resulting composited CVPixelBuffer will be passed to the video writer.

### **3.3 Media Writing (AVAssetWriter)**

All captured and processed streams will be written to a single file using AVAssetWriter to ensure perfect synchronization.

1. **File Format:** The output container format shall be **QuickTime Movie (.mov)**, which provides robust support for multiple discrete audio and video tracks.
2. **Writer Initialization:**
   * Instantiate an AVAssetWriter with the output file URL and .mov file type.
3. **Input Configuration:**
   * Create and add up to three AVAssetWriterInput instances to the writer:
     1. **Video Input:** Configured for the composited video stream.
     2. **Microphone Audio Input:** Configured for the de-interleaved microphone audio stream.
     3. **System Audio Input:** Configured for the de-interleaved system audio stream.
4. **Writing Process:**
   * Start the writing session using startWriting() and startSession(atSourceTime:).
   * As CMSampleBuffer objects are received from the audio and video capture callbacks, append them to their corresponding AVAssetWriterInput.
   * AVAssetWriter will use the presentation timestamps on each buffer to automatically interleave the data from all tracks, guaranteeing synchronization.7
5. **Finalization:**
   * Upon stopping the recording, call finishWriting(completionHandler:) to finalize the file and write all necessary metadata.

---

## **4.0 Post-Processing Pipeline Specification**

This pipeline runs offline after the recording is complete.

### **4.1 Audio Pre-processing**

1. **Audio Extraction:** Use a bundled ffmpeg command-line process to extract and mix the two separate audio tracks (microphone and system audio) from the recorded .mov file.
2. **Format Conversion:** The mixed audio must be converted to a **16-bit, 16kHz mono WAV file**, which is the required input format for the transcription and diarization models.7

### **4.2 Speech-to-Text**

The application will support two transcription engines, giving users a choice between optimal performance and open-source transparency.

#### **4.2.1 Primary Implementation: Apple Speech Framework (Recommended)**

For macOS 15+, Apple introduced new on-device speech recognition APIs that provide significant performance advantages:

1. **API:** Use the new **`SpeechAnalyzer`** and **`SpeechTranscriber`** classes introduced in macOS 15.
2. **Performance:** Testing shows Apple's framework transcribes approximately **2x faster than Whisper** on Apple Silicon with comparable accuracy.
3. **Optimization:** Automatically leverages the Apple Neural Engine (ANE) and is optimized for Apple Silicon without requiring model management.
4. **Privacy:** Fully on-device processing with no network requests.
5. **Timestamp Support:** The API provides word-level timestamps natively, which are essential for accurate diarization alignment.
6. **Rationale:** Since we target macOS 15+ exclusively, using Apple's latest speech APIs provides the best user experience with minimal implementation complexity. The framework is maintained by Apple and will receive ongoing optimizations.

#### **4.2.2 Alternative Implementation: WhisperKit (Open Source Option)**

For users who prefer an auditable, open-source transcription engine, the application will also support WhisperKit:

1. **Implementation:** Integrate **WhisperKit**, a Swift package that provides a high-performance, CoreML-optimized implementation of OpenAI's Whisper.9 This leverages the Apple Neural Engine (ANE) on Apple Silicon for maximum efficiency.
2. **Model Selection:** Users can choose from multiple English-only Whisper models based on their accuracy vs. speed preferences:
   * **base.en** (~75MB) - Fastest, good accuracy for clear speech
   * **small.en** (~150MB) - Balanced option (recommended default for Whisper)
   * **medium.en** (~750MB) - Highest accuracy, slower processing
3. **Core ML Optimization:** WhisperKit converts Whisper models to `.mlmodel`/`.mlmodelc` format, allowing the Neural Engine and GPU to accelerate inference. The encoder and decoder portions of the model can run on the ANE for significant performance gains.
4. **Timestamp Accuracy:** To achieve the precision needed for diarization, the implementation must generate **word-level timestamps**. This will be achieved using the forced-alignment methodology from **WhisperX**, which uses a secondary model to refine the timestamps provided by the base Whisper model.5
5. **Rationale:** Provides users who require open-source, auditable software with a proven transcription solution. Whisper is widely regarded as state-of-the-art for offline speech recognition.

#### **4.2.3 User Configuration**

The application Settings will allow users to:

* Choose between Apple Speech Framework (default) or WhisperKit
* If using WhisperKit, select the model size based on their hardware capabilities and accuracy requirements
* View estimated processing times for each option on their specific hardware

#### **4.2.4 Alternatives Considered**

* **Vosk (Kaldi-based):** Lightweight offline engine, but significantly lower accuracy than both Apple Speech and Whisper for conversational speech.
* **Coqui STT (DeepSpeech fork):** Another open-source option, but less accurate than Whisper and more complex to integrate.
* **whisper.cpp directly:** Could be used via C++ bridging, but WhisperKit provides better Swift integration and Core ML optimization out of the box.

### **4.3 Speaker Diarization (pyannote.audio)**

The system will use pyannote.audio to determine "who spoke when."

1. **Implementation:** The application will execute a Python script that utilizes the pyannote.audio library.12 This script will be called from the main Swift application.
2. **Model:** Use a state-of-the-art pretrained diarization pipeline, such as pyannote/speaker-diarization-3.1, available from the Hugging Face Hub.17 The user must agree to the model's terms and provide a Hugging Face access token within the application's settings.
3. **Output:** The diarization process will output a series of time-stamped segments, each with an assigned speaker label (e.g., SPEAKER\_00, SPEAKER\_01).

### **4.4 Transcript Generation and Synchronization**

This is the final step where the outputs from transcription and diarization are merged.

1. **Input:**
   * A list of words, each with a precise start and end time (from the WhisperX pipeline).
   * A list of speaker segments, each with a start time, end time, and speaker label (from pyannote.audio).
2. **Alignment Algorithm:**
   * For each word in the transcription output:
     * Calculate the temporal midpoint of the word: midpoint \= word.startTime \+ (word.endTime \- word.startTime) / 2\.
     * Iterate through the speaker segments from the diarization output to find the segment where segment.startTime \<= midpoint \< segment.endTime.
     * Assign the speaker label of the found segment to the word.16
3. **Final Output:**
   * Group consecutive words assigned to the same speaker into a single block.
   * Format the final transcript to display the start time, speaker label, and the block of text for each conversational turn.

---

## **5.0 Non-Functional Requirements**

### **5.1 Target Environment**

* **Operating System:** macOS 15.0 or later.
* **Hardware:** Apple Silicon (recommended) and Intel-based Macs.

### **5.2 Dependencies**

The project will require the following external dependencies:

#### **5.2.1 System-Level Dependencies (managed via Homebrew)**

* **ffmpeg:** For audio extraction, mixing, and format conversion in post-processing.

#### **5.2.2 Swift Package Manager Dependencies**

* **WhisperKit:** For local, high-performance transcription (optional, if user selects Whisper over Apple Speech).
  * Includes CoreML-optimized Whisper models
  * Model files are downloaded on-demand or bundled with the app
* *Optional:* **AudioKit** - Could simplify audio processing tasks (format conversion, waveform analysis) if needed, though AVFoundation covers most requirements.

#### **5.2.3 Python 3 Environment (managed via a bundled virtual environment)**

* **torch:** Core dependency for ML models (required by pyannote.audio).
* **pyannote.audio:** For speaker diarization.
* **whisperx:** For generating word-level timestamps when using WhisperKit (not needed for Apple Speech Framework).
* **huggingface\_hub:** To download pretrained diarization models.

#### **5.2.4 Model Files and Sizes**

**For Whisper (if selected):**

* **base.en:** ~75MB - Fast, good for clear speech
* **small.en:** ~150MB - Balanced (recommended default)
* **medium.en:** ~750MB - Highest accuracy
* Models are CoreML-optimized (`.mlmodelc` format) for Neural Engine acceleration

**For Speaker Diarization:**

* **pyannote/speaker-diarization-3.1:** ~100-200MB
* Requires user to accept model terms and provide Hugging Face access token
* Downloaded on first use and cached locally

**For Apple Speech Framework:**

* No model management required - uses system-provided models optimized for the device

### **5.3 Performance Considerations**

#### **5.3.1 Hardware Optimization**

The application is designed to leverage modern Mac hardware capabilities:

* **Apple Silicon (M1+):**
  * Primary target platform
  * Neural Engine acceleration for transcription (both Apple Speech and WhisperKit)
  * Unified memory architecture benefits media processing
  * Expected transcription speed: 2-10x faster than real-time (depending on model)

* **Intel Macs:**
  * Supported but with reduced performance
  * Core ML can utilize Intel GPUs for acceleration
  * Expected transcription speed: 0.5-2x real-time (depending on model and CPU)

#### **5.3.2 Processing Strategy**

* **Real-time Recording:** Minimal CPU overhead; media capture is hardware-accelerated
* **Post-Processing:** CPU/Neural Engine intensive
  * Transcription: Most resource-intensive task (5-30 minutes for 1-hour meeting)
  * Diarization: Moderate resource usage (2-10 minutes for 1-hour meeting)
  * User can continue working during post-processing; progress is shown in UI

#### **5.3.3 Model Selection Guidance**

The application will provide recommendations based on detected hardware:

* **Apple Silicon M1/M2/M3+:** Apple Speech Framework (default) or any Whisper model
* **Intel Mac (modern):** Apple Speech Framework (default) or Whisper base.en/small.en
* **Intel Mac (older):** Apple Speech Framework only (best performance)

### **5.4 Permissions**

The application must correctly request and handle the following system permissions:

* **Microphone Access:** NSMicrophoneUsageDescription
* **Camera Access:** NSCameraUsageDescription (for optional webcam recording)
* **Screen Recording:** Handled by the system when ScreenCaptureKit is initiated.
* **System Audio Capture:** NSAudioCaptureUsageDescription.1

---

## **6.0 High-Level User Interface (UI) Flow**

The application will feature a simple, intuitive interface built with SwiftUI.

1. **Main View:**
   * Displays a list of past recordings with thumbnails, duration, and transcription status.
   * A prominent "New Recording" button.
   * Access to Settings (gear icon).

2. **Settings View:**
   * **Transcription Engine:** Toggle between Apple Speech Framework (default) and WhisperKit
   * **Whisper Model Selection:** If WhisperKit is selected, choose model size (base.en, small.en, medium.en)
   * **Hardware Info:** Display detected hardware capabilities and recommended settings
   * **Hugging Face Token:** Input field for pyannote.audio model access
   * **Audio Quality:** Recording bitrate and format options
   * **Storage Location:** Where to save recordings and transcripts

3. **Recording Setup View:**
   * Dropdowns or toggles to select audio inputs (microphone) and enable/disable system audio capture.
   * A toggle to enable video recording.
   * If video is enabled, options to select a source (full display, application window, or webcam). A live preview will be shown.
   * A "Start Recording" button.

4. **Recording State:**
   * A minimal UI element (e.g., a menu bar icon) indicates that a recording is in progress.
   * Live recording timer and file size indicator.
   * Controls to pause and stop the recording.

5. **Post-Recording:**
   * A progress indicator shows the status of the offline transcription and diarization process.
   * Separate progress bars for transcription and diarization stages.
   * Estimated time remaining based on recording length and selected engine.
   * Option to cancel processing (keeps the raw recording).

6. **Transcript View:**
   * Displays the final, diarized transcript alongside the recording.
   * The recording can be played back, with the corresponding text highlighted.
   * Speaker labels are color-coded for easy identification.
   * Options to:
     * Edit speaker names (replace "SPEAKER_00" with "John Smith")
     * Export the transcript (plain text, SRT, VTT, JSON)
     * Export the recording (original multi-track or mixed audio)
     * Search within the transcript
     * Jump to specific timestamps

### **Works cited**

1. Capturing system audio with Core Audio taps | Apple Developer Documentation, accessed October 23, 2025, [https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps](https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps)
2. AudioTee: capture system audio output on macOS \- Nick Payne @ Strongly Typed Ltd, accessed October 23, 2025, [https://stronglytyped.uk/articles/audiotee-capture-system-audio-output-macos](https://stronglytyped.uk/articles/audiotee-capture-system-audio-output-macos)
3. ScreenCaptureKit | Apple Developer Documentation, accessed October 23, 2025, [https://developer.apple.com/documentation/screencapturekit/](https://developer.apple.com/documentation/screencapturekit/)
4. Capturing screen content in macOS | Apple Developer Documentation, accessed October 23, 2025, [https://developer.apple.com/documentation/ScreenCaptureKit/capturing-screen-content-in-macos](https://developer.apple.com/documentation/ScreenCaptureKit/capturing-screen-content-in-macos)
5. Screen recording software with possibility to record specific window/app : r/macapps, accessed October 23, 2025, [https://www.reddit.com/r/macapps/comments/1f5hraj/screen\_recording\_software\_with\_possibility\_to/](https://www.reddit.com/r/macapps/comments/1f5hraj/screen_recording_software_with_possibility_to/)
6. The Fastest Open Source Speech Recognition Models in 2025 \- SiliconFlow, accessed October 23, 2025, [https://www.siliconflow.com/articles/en/fastest-open-source-speech-recognition-models](https://www.siliconflow.com/articles/en/fastest-open-source-speech-recognition-models)
7. How to use AVAssetReader and AVAssetWriter for multiple tracks (audio and video) simultaneously? \- Stack Overflow, accessed October 23, 2025, [https://stackoverflow.com/questions/5240581/how-to-use-avassetreader-and-avassetwriter-for-multiple-tracks-audio-and-video](https://stackoverflow.com/questions/5240581/how-to-use-avassetreader-and-avassetwriter-for-multiple-tracks-audio-and-video)
8. AVAssetWriter | Apple Developer Documentation, accessed October 23, 2025, [https://developer.apple.com/documentation/avfoundation/avassetwriter](https://developer.apple.com/documentation/avfoundation/avassetwriter)
9. AVFoundation Programming Guide \- Export \- Will's Blog, accessed October 23, 2025, [https://gewill.org/2016/05/03/AVFoundation-Programming-Guide-Export/](https://gewill.org/2016/05/03/AVFoundation-Programming-Guide-Export/)
10. 7 Best Speech Recognition Software Mac Users Need in 2025 \- Murmurtype.me, accessed October 23, 2025, [https://murmurtype.me/speech-recognition-software-mac](https://murmurtype.me/speech-recognition-software-mac)
11. Top 8 open source STT options for voice applications in 2025 \- AssemblyAI, accessed October 23, 2025, [https://www.assemblyai.com/blog/top-open-source-stt-options-for-voice-applications](https://www.assemblyai.com/blog/top-open-source-stt-options-for-voice-applications)
12. Top 8 speaker diarization libraries and APIs in 2025 \- AssemblyAI, accessed October 23, 2025, [https://www.assemblyai.com/blog/top-speaker-diarization-libraries-and-apis](https://www.assemblyai.com/blog/top-speaker-diarization-libraries-and-apis)
13. capture system audio on macOS : r/swift \- Reddit, accessed October 23, 2025, [https://www.reddit.com/r/swift/comments/1l74ee7/capture\_system\_audio\_on\_macos/](https://www.reddit.com/r/swift/comments/1l74ee7/capture_system_audio_on_macos/)
14. Top 6 Open Source Transcription Software Tools in 2025 \- Amical, accessed October 23, 2025, [https://amical.ai/blog/open-source-transcription-software](https://amical.ai/blog/open-source-transcription-software)
15. AVAssetWriterInputGroup | Apple Developer Documentation, accessed October 23, 2025, [https://developer.apple.com/documentation/avfoundation/avassetwriterinputgroup](https://developer.apple.com/documentation/avfoundation/avassetwriterinputgroup)
16. Transcription and diarization (speaker identification) · openai whisper · Discussion \#264, accessed October 23, 2025, [https://github.com/openai/whisper/discussions/264](https://github.com/openai/whisper/discussions/264)
17. How do I screen record on mac with audio? \- Microsoft Community Hub, accessed October 23, 2025, [https://techcommunity.microsoft.com/discussions/windowsinsiderprogram/how-do-i-screen-record-on-mac-with-audio/4382388](https://techcommunity.microsoft.com/discussions/windowsinsiderprogram/how-do-i-screen-record-on-mac-with-audio/4382388)
18. Hands-On: How Apple's New Speech APIs Outpace Whisper for Lightning-Fast Transcription \- MacStories, accessed October 23, 2025, [https://www.macstories.net/stories/hands-on-how-apples-new-speech-apis-outpace-whisper-for-lightning-fast-transcription/](https://www.macstories.net/stories/hands-on-how-apples-new-speech-apis-outpace-whisper-for-lightning-fast-transcription/)
19. Setting Up a Capture Session | Apple Developer Documentation, accessed October 23, 2025, [https://developer.apple.com/documentation/avfoundation/setting-up-a-capture-session](https://developer.apple.com/documentation/avfoundation/setting-up-a-capture-session)
20. SwiftWhisper \- Swift wrapper for OpenAI's Whisper model, accessed October 23, 2025, [https://github.com/exPHAT/SwiftWhisper](https://github.com/exPHAT/SwiftWhisper)
