
# **A Technical Blueprint for Building a Local Meeting Recorder and Transcription System on macOS**

## **I. Architectural Foundations: Core Decisions for macOS Media Capture**

This section establishes the high-level technical strategy for the application. The decisions made here will dictate the application's capabilities, backward compatibility, and overall user experience. The analysis focuses on selecting the optimal frameworks and architectural patterns to address the fundamental challenges of real-time, multi-stream media capture on the macOS platform.

### **1.1. System Audio Capture Strategy: A Foundational Dilemma**

The primary engineering challenge on macOS is that the operating system, by design, provides no native, direct API for an application to capture the audio output of another application or the system as a whole.1 This security-oriented design choice prevents trivial eavesdropping but necessitates a deliberate architectural workaround for legitimate use cases such as meeting recording. The research reveals two distinct paths to solving this problem: the long-standing Virtual Audio Device method and the modern Core Audio Taps API.

#### **Method 1: Virtual Audio Devices (VADs) \- The Established Workaround**

The most common and historically significant method for capturing system audio involves the installation of a kernel extension (kext) or a modern driver extension that creates a virtual audio device. This device appears to the operating system just like a physical microphone or speaker, allowing audio to be programmatically routed through it for capture.4

The principle of operation requires a two-part configuration within the macOS Core Audio subsystem. First, a **Multi-Output Device** is created to split the system's audio stream, sending it simultaneously to the user's physical speakers (so they can hear the meeting) and to the virtual audio device for capture. Second, an **Aggregate Device** is created to combine the virtual audio device (now receiving system audio) and the physical microphone input into a single, multi-channel input source that the recording application can listen to.6

Several implementations of this VAD approach exist:

* **Soundflower**: An early, open-source kernel extension that was once the standard for inter-application audio routing. However, it has not been actively maintained for modern versions of macOS, is known for instability, and its reliance on deprecated kernel extension technology makes it an unsuitable choice for a new project.4
* **BlackHole**: The modern, open-source, and actively maintained successor to Soundflower.4 Developed by Existential Audio, BlackHole is a virtual audio loopback driver that is compatible with modern macOS versions (10.10 and newer) and runs natively on both Intel and Apple Silicon hardware.12 It has become the de facto standard for free, reliable VAD solutions on macOS.
* **Commercial Alternatives**: Proprietary applications such as Rogue Amoeba's Loopback and Audio Hijack provide a more polished user interface and advanced, flexible routing capabilities.16 While powerful, they are closed-source, paid products and are not suitable as a redistributable component of a custom-built application.

The VAD approach, while effective, introduces complexity. It requires either manual user configuration in the Audio MIDI Setup utility or sophisticated programmatic setup by the application itself. Furthermore, combining devices with different hardware clocks can lead to synchronization issues, or "drift," which must be managed by Core Audio's "Drift Correction" feature, adding another layer of complexity.14

#### **Method 2: Core Audio Taps API \- The Modern, Native Approach**

With the release of macOS 14.2 and subsequent enhancements in macOS 14.4, Apple introduced a native, user-space API for system audio capture within the Core Audio framework.20 This represents a significant philosophical shift, acknowledging the legitimacy of this use case and providing a sanctioned, secure alternative to third-party kernel extensions.

This modern approach allows an application to directly "tap into" the audio stream of the entire system or a specific application identified by its process ID (PID).20 The implementation involves using a sequence of Core Audio functions, primarily AudioHardwareCreateProcessTap to establish the tap and AudioHardwareCreateAggregateDevice to combine the tap's output with other audio sources, such as a microphone.20

To use this API, an application must include the NSAudioCaptureUsageDescription key in its Info.plist file. This provides the user-facing string for a system permission prompt. The system leverages the existing Screen Recording permission infrastructure to manage user consent for audio capture, reinforcing the idea that this is a trusted, user-authorized operation.20 Open-source projects like AudioCap and AudioTee serve as valuable reference implementations for this new API.20

The introduction of this native API has profound architectural implications. For years, the absence of such a feature forced the developer community into the realm of kernel-level workarounds, which Apple has been systematically deprecating due to security concerns. The Core Audio Taps API provides a stable, future-proof path that aligns with Apple's long-term platform strategy. It simplifies the software stack, eliminating the need to bundle a third-party driver, manage installation and permissions for kernel extensions, and handle the complexities of virtual device setup. This reduces development and maintenance overhead and provides a much smoother, more secure user experience.

#### **Architectural Decision and Justification**

For this project, a hybrid architectural approach is recommended to achieve the best balance of modern technology and backward compatibility.

The primary implementation path should target the **Core Audio Taps API**. This is the technically superior solution for supported systems (macOS 14.2+), offering a more stable, secure, and user-friendly experience that is aligned with Apple's platform direction.

As a fallback for users on older macOS versions (macOS 10.10 through 14.1), the application should support the **BlackHole Virtual Audio Device** method. This ensures the application remains functional for a wider user base while clearly delineating the VAD approach as a legacy support feature. This dual strategy allows the project to leverage the best of the modern macOS ecosystem without sacrificing accessibility.

| Feature | Virtual Audio Device (BlackHole) | Core Audio Taps API |
| :---- | :---- | :---- |
| **macOS Version** | macOS 10.10+ 15 | macOS 14.2+ 21 |
| **Dependencies** | Requires third-party driver installation 7 | Native macOS framework, no external drivers 20 |
| **User Setup** | Complex manual or programmatic setup of Multi-Output and Aggregate Devices 6 | Simpler programmatic setup; tied to system Screen Recording permission prompt 20 |
| **Stability** | Prone to clock drift, requiring "Drift Correction"; potential for conflicts 14 | Managed by Core Audio; expected to be more stable and robust |
| **Implementation** | Interacts with devices via standard Core Audio/AVFoundation APIs after setup | Uses specific new Core Audio functions (AudioHardwareCreateProcessTap) 21 |
| **Maintenance** | Dependent on third-party driver updates | Maintained by Apple as part of macOS |

### **1.2. Video & Screen Capture Framework Selection**

The user's requirement for optional video recording of the screen or a specific application window necessitates the selection of an appropriate capture framework. macOS offers several APIs for this purpose, reflecting an evolution from older, more limited frameworks to modern, high-performance alternatives.

* **AVFoundation (AVCaptureScreenInput)**: This is the legacy API for screen capture on macOS.24 While it is functional for basic full-screen recording, Apple's official documentation explicitly recommends ScreenCaptureKit as its replacement for macOS 12.3 and later.24 AVCaptureScreenInput is less efficient, offers less granular control over what is captured, and has been observed to have issues with color space accuracy in certain workflows.26
* **ReplayKit**: Introduced for in-app content recording, particularly in games, ReplayKit is available on macOS 11.0 and later.27 It provides a simpler, higher-level API but lacks the fine-grained control necessary for a tool designed to capture arbitrary windows from other applications. Its focus is on recording the content of the host app itself, making it unsuitable for this project's goals.28
* **ScreenCaptureKit**: Introduced in macOS 12.3, ScreenCaptureKit is Apple's state-of-the-art framework for high-performance, low-latency screen capture.31 It was designed specifically to address the shortcomings of older APIs, providing a robust and efficient solution for professional applications. Its key advantages include the ability to get a list of all shareable content (windows, applications, and displays) via SCShareableContent and to precisely target that content using an SCContentFilter.33 This gives the developer full control over the capture source, which is essential for recording a specific meeting application window while excluding other on-screen elements.

#### **Architectural Decision and Justification**

The definitive choice for this project is **ScreenCaptureKit**. Its superior performance, granular control over content selection, and official status as Apple's recommended framework make it the only logical selection.24 While ScreenCaptureKit will be used for capturing the screen or application window, the broader AVFoundation framework will still play a role in capturing the webcam feed via AVCaptureSession and in the final media writing process with AVAssetWriter.

### **1.3. Multi-Stream Recording and Synchronization Architecture**

The application must be capable of capturing up to three distinct media streams simultaneously—microphone audio, system audio, and video—and writing them into a single, perfectly synchronized file. This requires a robust architecture for managing and multiplexing these streams.

* **Capture and Track Separation**: Each media source will be captured and treated as an independent stream. The microphone audio and system audio will be captured as separate channels from the aggregate audio device and then programmatically separated. The video will be captured as a distinct stream from ScreenCaptureKit. Each of these streams will be written to its own dedicated track within the output media file. This separation is critical for the post-processing pipeline; it allows the transcription and diarization models to work on a mix of the audio tracks while preserving the clean, isolated sources for any future analysis or debugging.
* **Synchronization Mechanism**: The key to maintaining synchronization across tracks is the meticulous handling of presentation timestamps. Both Core Audio (AudioBufferList) and ScreenCaptureKit (CMSampleBuffer) provide timestamps for every packet of media data they deliver. The AVAssetWriter class in AVFoundation is specifically designed to use these timestamps to correctly interleave the data from multiple tracks into a single container file, ensuring that audio and video remain perfectly aligned during playback.36
* **File Format Selection**: The choice of container format is crucial for supporting multiple tracks and ensuring broad compatibility.
  * **MOV (QuickTime Movie)**: This is the ideal format for the project. As the native container format for macOS, it has robust, first-class support for multiple discrete audio and video tracks within AVFoundation and AVAssetWriter.38
  * **MP4**: While widely used, its support for multiple, selectable audio tracks can be less consistent across different media players and editing software when compared to the MOV format.38
  * **CAF (Core Audio Format)**: This format is excellent for complex, multi-channel audio-only recordings and can handle extremely large files without the 4 GB limitation of older formats like WAV.41 However, it is not a standard container for video content.

#### **Architectural Decision and Justification**

The recording architecture will employ **AVAssetWriter** to multiplex one video track (from ScreenCaptureKit) and two discrete audio tracks (microphone and system audio) into a single **.mov file**. This approach creates a standard, flexible, and easily parsable output file that preserves the individual data streams while guaranteeing their temporal synchronization, providing an ideal input for the post-processing pipeline.

## **II. Implementation Deep Dive: The Capture Engine**

This section provides a granular, technical blueprint for constructing the application's real-time capture component. It translates the architectural decisions from the previous section into a concrete implementation plan, detailing the specific APIs and logic required to configure the audio environment, capture all media streams, and write them to a synchronized file.

### **2.1. Programmatic Audio Environment Configuration**

A core requirement for a seamless user experience is the automatic configuration of the audio environment. The application must not require the user to manually open the Audio MIDI Setup utility. This setup and teardown process should be handled programmatically on application launch and exit. The implementation will rely heavily on the low-level CoreAudio.framework.

#### **Implementation for VAD (BlackHole) Fallback Path**

For systems running macOS versions prior to 14.2, the application will fall back to using the BlackHole virtual audio device. The setup involves creating two virtual devices.

1. **Device Enumeration**: Upon launch, the application must first identify the unique AudioDeviceID for three key devices: the user's selected microphone (e.g., "Built-in Microphone"), the primary system output (e.g., "MacBook Pro Speakers"), and the "BlackHole 2ch" virtual device. This is achieved by querying the system for a list of all available audio devices using AudioObjectGetPropertyData with the kAudioHardwarePropertyDevices selector and then iterating through them to find the desired devices by name or UID.
2. **Create Multi-Output Device**: To ensure the user can both hear the meeting and the application can capture it, a Multi-Output Device is required. This is created programmatically using the AudioHardwareCreateAggregateDevice function. The critical detail is the configuration dictionary passed to this function. It must contain the UIDs of the primary output device and the BlackHole device. Most importantly, the dictionary must include the key kAudioAggregateDeviceIsStackedKey set to true.43 This key instructs Core Audio to create a Multi-Output Device that duplicates the audio stream to all its sub-devices, rather than a standard Aggregate Device which concatenates their channels.43
3. **Create Aggregate Device**: To capture both microphone and system audio simultaneously, a standard Aggregate Device is created. This is done by calling AudioHardwareCreateAggregateDevice again, but this time without the "stacked" key. The configuration dictionary should list the UIDs of the user's microphone and the BlackHole device as sub-devices.44 This combines the two distinct audio sources into a single, multi-channel virtual input device that the application can record from.
4. **Set System Default Devices**: To activate this routing, the application must programmatically set the system's default audio output to the newly created Multi-Output Device. This is accomplished using AudioObjectSetPropertyData on the system object (kAudioObjectSystemObject) with the property kAudioHardwarePropertyDefaultOutputDevice.46 Upon application exit, it is crucial to restore the user's original default output device to avoid leaving the system in a modified state.

#### **Implementation for Core Audio Taps Path**

For systems running macOS 14.2 or later, the setup is significantly simpler and does not require a Multi-Output Device.

1. **Create Audio Tap**: The application first requests permission to capture system audio, which triggers the standard Screen Recording system prompt. Once granted, it creates a tap on the system audio output using AudioHardwareCreateProcessTap and a corresponding CATapDescription.20
2. **Create Aggregate Device**: An Aggregate Device is still required to combine the audio from the tap with the audio from the user's physical microphone. This is created using AudioHardwareCreateAggregateDevice. The configuration dictionary will specify the UID of the newly created tap and the UID of the physical microphone in its sub-device list.21
3. **Set Input Device**: The application then configures its audio capture session to use this new aggregate device as its input source. The system's default output device remains untouched, providing a much less intrusive user experience.

### **2.2. Capturing and De-interleaving Multi-Channel Audio**

Regardless of the setup method, the result is an Aggregate Device that presents a single, multi-channel audio stream to the application. For instance, combining a stereo microphone (2 channels) and the stereo BlackHole device (2 channels) results in a 4-channel input device. The raw audio data arrives within a Core Audio callback as an AudioBufferList structure.

A fundamental and often overlooked challenge in this architecture is the issue of clock drift. When multiple audio devices are combined, each operates on its own internal hardware clock. These clocks, no matter how precise, will inevitably run at slightly different rates, causing them to "drift" apart over time. This drift manifests as audible pops, clicks, and a progressive loss of synchronization between the streams.14 Core Audio provides a built-in solution to this problem. When an Aggregate Device is created, one of its sub-devices must be designated as the "Clock Source" or master clock.47 For all other sub-devices in the aggregate, "Drift Correction" must be enabled.6 This engages a sophisticated real-time resampling algorithm within Core Audio that dynamically adjusts the sample rate of the slave devices to keep them perfectly locked to the master clock. When creating the Aggregate Device programmatically, this is not an optional tweak but a mandatory configuration step. The configuration dictionary must specify the master device's UID for the kAudioAggregateDeviceMasterSubDeviceKey and set the kAudioSubDeviceDriftCompensationKey to true for all other sub-devices.44 Failure to implement this correctly is a primary source of instability and audio artifacts in multi-device recording setups.

* **Channel Mapping**: The order of the channels within the aggregate device's stream is determined by the order in which the sub-devices were added during its creation.47 The application code must be aware of this mapping to correctly identify which channels correspond to the microphone and which correspond to the system audio. For example, if the microphone was added first, its left and right channels might be channels 0 and 1, while the system audio's channels would be 2 and 3\.
* **De-interleaving Process**: The primary task within the audio capture callback is to de-interleave these channels into separate logical streams. The AudioBufferList may contain data in one of two formats:
  * **Non-interleaved**: Each buffer in the list (mBuffers\[i\]) represents a single channel. This is the simpler case.
  * Interleaved: A single buffer contains samples from multiple channels alternating (e.g., L, R, L, R,...).
    The application must inspect the AudioStreamBasicDescription to determine the format. The goal is to produce two separate, clean audio buffers: one for the microphone and one for the system audio.

The conceptual logic involves iterating through the incoming frames. For each frame, the sample data from the microphone channels is copied into a dedicated "micBuffer," and the sample data from the system audio channels is copied into a "systemAudioBuffer." This manual separation is the essence of de-interleaving the aggregate stream.49 These newly created, separate buffers are then wrapped in CMSampleBuffer objects and passed to their respective AVAssetWriterInput instances for writing to the file.

### **2.3. Implementing Video Capture with ScreenCaptureKit and AVFoundation**

The video capture component will be built primarily using ScreenCaptureKit, with AVFoundation used for webcam integration and compositing.

* **Screen Capture with ScreenCaptureKit**:
  1. **Request Access and Enumerate Content**: The application must have the system's Screen Recording permission. On first run, it will use SCShareableContent.current to asynchronously fetch a list of all capturable windows, applications, and displays.31 This list is used to populate a user interface, allowing the user to select the specific content to record (e.g., the Zoom window).
  2. **Filter and Configure**: Based on the user's selection, an SCContentFilter is created to isolate the desired content.33 An SCStreamConfiguration object is then configured with parameters such as resolution (width, height), frame rate (minimumFrameInterval), and buffer depth (queueDepth).33
  3. **Start Stream**: An SCStream is initialized with the filter and configuration. The application provides an object conforming to the SCStreamOutput protocol to serve as the delegate. Calling startCapture() begins the stream, and the delegate method stream(\_:didOutputSampleBuffer:of:) will be called repeatedly with CMSampleBuffer objects containing the screen video frames.33
* **Webcam Capture with AVFoundation**:
  1. **Session Setup**: A standard AVCaptureSession is instantiated.52
  2. **Device Input**: The desired webcam device is located (e.g., via AVCaptureDevice.default()) and used to create an AVCaptureDeviceInput, which is then added to the session.54
  3. **Data Output**: An AVCaptureVideoDataOutput is added to the session. A delegate is set on this output to receive raw video frames as CMSampleBuffer objects in its captureOutput(\_:didOutputSampleBuffer:from:) callback.55
  4. **Start Session**: The startRunning() method is called on the session to begin the flow of video data from the webcam.
* Real-Time Compositing for Picture-in-Picture:
  Since AVAssetWriter can only accept one video source per track, the screen capture and webcam streams must be composited into a single video stream in real time. This is a computationally intensive task that can be achieved using AVFoundation's composition tools or lower-level frameworks like Core Image or Metal. A practical approach using AVMutableVideoComposition involves creating a composition that, for each frame timestamp, layers the scaled-down webcam frame on top of the full-size screen capture frame.56 This generates a new, final CVPixelBuffer for each frame, which is then passed to the video AVAssetWriterInput.

### **2.4. Writing to a Multi-Track Media File with AVAssetWriter**

AVAssetWriter is the AVFoundation class responsible for encoding and writing media data to a container file. It is capable of handling multiple input sources and writing them to separate tracks within a single file, automatically managing the interleaving and synchronization based on the provided timestamps.

1. **Initialization**: An AVAssetWriter instance is created, specifying the output file URL and the container type, which will be AVFileType.mov.57
2. **Input Configuration**: Three separate AVAssetWriterInput instances are created:
   * One for video, configured with the appropriate video settings (codec, dimensions).
   * One for the microphone audio track.
   * One for the system audio track.
     Each of these inputs is added to the AVAssetWriter instance using the add(\_:) method.37
3. **Writing Process**:
   * The writing process is initiated by calling startWriting() followed by startSession(atSourceTime:).
   * As the various capture callbacks are invoked, the application receives media data (the composited video CMSampleBuffer, the de-interleaved mic audio buffer, and the de-interleaved system audio buffer).
   * Each buffer, correctly wrapped in a CMSampleBuffer with its presentation timestamp, is appended to the corresponding AVAssetWriterInput using its append(\_:) method. The asset writer's internal logic uses the timestamps to ensure all data is written in the correct order to maintain sync across all tracks.37
4. **Finalization**: Once the recording is stopped, the finishWriting(completionHandler:) method is called on the AVAssetWriter. This finalizes the writing process, computes and writes the necessary container file headers and metadata, and closes the file.

## **III. The Post-Processing Pipeline: From Raw Media to Structured Insights**

After the real-time capture phase concludes, the application transitions to the post-processing pipeline. This offline stage is where the raw, multi-track media file is transformed into a structured, diarized transcript. This involves three key steps: high-performance speech-to-text conversion, speaker diarization, and the critical alignment of their respective outputs.

### **3.1. High-Performance Speech-to-Text with Whisper**

The core of the transcription engine is OpenAI's Whisper, a state-of-the-art open-source automatic speech recognition (ASR) model renowned for its accuracy across a wide range of languages, accents, and acoustic conditions.58 For a responsive desktop application, the key consideration is not the model itself, but the runtime environment used for its execution. The goal is to achieve fast, accurate, and entirely local transcription without relying on cloud APIs.

* **Implementation Options Analysis**:
  * **Python (openai-whisper)**: This is the official reference implementation from OpenAI. While straightforward to set up using pip, it relies on the PyTorch framework for execution.58 On Apple Silicon, PyTorch's performance is not fully optimized to leverage the Apple Neural Engine (ANE), resulting in slower inference times and higher CPU/GPU utilization compared to native solutions. This makes it less suitable for a snappy, resource-efficient desktop application.
  * **whisper.cpp**: This is a highly optimized C++ port of the Whisper model, specifically tailored for high performance on a variety of hardware, including Apple Silicon.62 It leverages low-level optimizations, including ARM NEON, the Accelerate framework, and a Metal backend for GPU-accelerated inference.63 It can be compiled as a static or dynamic library and integrated into a native macOS application via an Objective-C++ wrapper, offering a significant performance improvement over the Python version.
  * **CoreML-based Frameworks (e.g., WhisperKit)**: This approach involves converting the Whisper model weights into Apple's proprietary CoreML format. This allows the model to be executed directly on the Apple Neural Engine (ANE), a specialized processor on Apple Silicon chips designed for efficient machine learning inference.64 Frameworks like WhisperKit abstract away the complexities of model conversion and inference, providing a simple Swift package that can be easily integrated into a macOS application.66 This method yields the best performance-per-watt, resulting in the fastest transcription speeds and lowest battery consumption, which are paramount for a positive user experience on a laptop.62
* **Recommendation and Justification**: For a native macOS application built with Swift or Objective-C, a **CoreML-based implementation such as WhisperKit is the optimal choice**. It delivers superior performance and energy efficiency by fully leveraging the dedicated ML hardware on Apple Silicon.66 This translates directly to a faster, more responsive user experience. whisper.cpp stands as a strong second option, especially if a C++-centric toolchain is preferred or if cross-platform compatibility is a future consideration.

| Implementation | Primary Language | Key Dependencies | Performance on Apple Silicon | Resource Usage | Ease of Integration (Swift/Obj-C) |
| :---- | :---- | :---- | :---- | :---- | :---- |
| **Official Python** | Python | PyTorch, FFmpeg 58 | Slowest (CPU/GPU via PyTorch) | High CPU/Memory, no ANE usage | Difficult (requires Python runtime embedding) |
| **whisper.cpp** | C++ | Accelerate, Metal, CoreML (optional) 63 | Fast (CPU, Metal GPU, optional ANE via CoreML backend) 62 | Moderate CPU/GPU, efficient memory | Moderate (requires C++ interop/Objective-C++ wrapper) |
| **WhisperKit (CoreML)** | Swift | CoreML, AVFoundation 66 | Fastest (Optimized for Apple Neural Engine) | Lowest power, optimized for ANE | Easiest (Native Swift package) 66 |

### **3.2. Speaker Diarization with Open-Source Toolkits**

Speaker diarization is the process of partitioning an audio stream into segments and assigning each segment a speaker label, thereby answering the question "who spoke when?".69 This is achieved by analyzing the audio to extract unique voice characteristics (speaker embeddings) and then clustering segments with similar characteristics.70

* **Library Selection**: The open-source landscape for speaker diarization is rich, but a few toolkits stand out for their performance and ease of use.
  * **pyannote.audio**: A state-of-the-art, PyTorch-based toolkit that has become a leading choice for speaker diarization.71 It provides pre-trained pipelines on the Hugging Face Hub, is well-documented, and is frequently used in combination with Whisper to create diarized transcripts.73 It officially supports macOS, making it a highly suitable choice.76
  * **NVIDIA NeMo**: A comprehensive conversational AI toolkit that includes powerful diarization models, including end-to-end architectures like Sortformer.77 While highly capable, NeMo is a larger, more complex framework primarily targeting researchers and enterprise environments with NVIDIA GPU hardware, making it less ideal for a lightweight local desktop application.73
  * **SpeechBrain**: Another all-in-one PyTorch-based conversational AI toolkit with support for speaker diarization.79 It offers a large number of pre-trained models and is known for its comprehensible tutorials, making it a strong alternative to pyannote.audio.73
  * **Kaldi**: A foundational toolkit for speech recognition research, written in C++. While it can be used for diarization, it has a very steep learning curve and is not designed for quick, straightforward implementation in a production application.73
* **Recommendation and Justification**: **pyannote.audio is the recommended library for this project.** Its excellent performance, availability of high-quality pre-trained models, strong community support, and established track record of successful integration with Whisper make it the most pragmatic and effective choice.81
* **Implementation**: The application will execute a Python script that leverages the pyannote.audio library. This script will load a pre-trained diarization pipeline (e.g., pyannote/speaker-diarization-3.1) from Hugging Face, apply it to the recorded audio file, and output a list of time-stamped segments, each associated with a generic speaker label (e.g., SPEAKER\_00, SPEAKER\_01, etc.).71

| Library | Key Architecture | Ease of Use | Pre-trained Models | Suitability for macOS |
| :---- | :---- | :---- | :---- | :---- |
| **pyannote.audio** | Modular (VAD, Embedding, Clustering) 85 | High (Simple Python API) 71 | Excellent (Hugging Face Hub) 74 | High (Python-based, runs on macOS) 76 |
| **NVIDIA NeMo** | Modular & End-to-End (Sortformer) 77 | Moderate (Toolkit for researchers) 73 | Good (NGC Catalog) 86 | Moderate (Optimized for Linux/NVIDIA GPUs) |
| **SpeechBrain** | Modular (PyTorch-based) 79 | High (Good tutorials) 73 | Good (Hugging Face Hub) 79 | High (Python-based, runs on macOS) |
| **Kaldi** | Modular (C++) 73 | Low (Steep learning curve) 73 | Available, but requires more setup | Moderate (Requires compilation) |

### **3.3. Synchronization and Final Transcript Generation**

The final and most critical step in the post-processing pipeline is the fusion of the transcription and diarization outputs. The accuracy of this alignment determines the ultimate utility of the final transcript.

* **The Timestamp Accuracy Problem**: The standard Whisper model provides timestamps at the utterance or segment level, and these can be inaccurate by several seconds.87 Attempting to align these coarse timestamps with the precise speaker segments from pyannote.audio would lead to significant errors, with entire sentences being misattributed to the wrong speaker.
* **The WhisperX Enhancement**: To solve this, the project should adopt the methodology popularized by the WhisperX open-source project.87 WhisperX improves upon the base Whisper model by using a secondary, phoneme-based ASR model (such as wav2vec2) to perform forced alignment. This process takes the text generated by Whisper and forces it to align with the audio on a phoneme-by-phoneme basis, resulting in highly accurate word-level timestamps.87 This level of temporal precision is non-negotiable for accurate diarization.
* **Proposed Alignment Algorithm**:
  1. **Step 1: Transcription with Word-Level Timestamps**: The first step is to process the mixed audio track from the recorded .mov file through a WhisperX-style pipeline. This will yield a structured output containing a list of every word spoken, each with its own precise start and end time.
  2. **Step 2: Speaker Diarization**: In parallel, the same mixed audio track is processed by the pyannote.audio pipeline. This produces a list of speaker segments, each defined by a start time, an end time, and a speaker label (e.g., SPEAKER\_00).
  3. **Step 3: Alignment and Merging**: The core logic of the synchronization process is to iterate through each word from the transcription output and assign it to a speaker.
     * For each word, calculate its temporal midpoint: midpoint \= word.start\_time \+ (word.end\_time \- word.start\_time) / 2\.
     * Search through the list of speaker segments from the diarization output to find the segment whose time range \[segment.start\_time, segment.end\_time\] contains the word's midpoint.
     * Assign the speaker label of that containing segment to the word.
     * This process effectively "tags" every single word in the transcript with the person who spoke it.75
  4. **Step 4: Transcript Formatting**: The final step is to render this tagged data structure into a human-readable format. Consecutive words attributed to the same speaker are grouped together into paragraphs or conversational turns. Each turn is then prepended with its start timestamp and the assigned speaker label, producing the final, diarized transcript.

## **IV. System Integration and Development Roadmap**

This final section provides a holistic view of the complete system architecture, outlines the necessary toolchain for development, and proposes a strategic, phased roadmap for building the application from a minimum viable product to a feature-complete tool.

### **4.1. Comprehensive System Architecture Diagram**

The system is best understood as two distinct but connected data flows: a real-time capture flow and an offline post-processing flow.

**Real-time Capture Flow (During the Meeting):**

\[Physical Mic\] \-\> \[Core Audio\] \-\> | |

| | \-\> \[Capture Engine\]
 \-\>   \-\> | (Multi-channel Interleaved) | (De-interleaving)

| |
                                  \+-------------------------------+
|
|
            \+-----------------------------------------+-----------------------------------------+

| (Mic Stream) | (System Audio Stream) |
| | |
 \-\> \-\> \-\> \-\> \[Multi-track.mov file\]
 \-\> \[AVFoundation\] \-\> \[Compositor\] \-\> | | |
                                                      \+-----------------------------------------+

This diagram illustrates how physical and virtual audio sources are combined into a single aggregate device. The application's capture engine taps into this device, de-interleaves the audio into separate microphone and system streams, and optionally composites screen and webcam video. Finally, AVAssetWriter multiplexes these independent streams into separate tracks within a single .mov file.

**Post-Processing Flow (After the Meeting):**

\[Multi-track.mov file\] \-\> \[FFmpeg (Audio Extraction)\] \-\>
|
            \+--------------------------------------------------+--------------------------------------------------+

| | |
            v                                                  v |
                                \[pyannote.audio Pipeline\] |
 (Whisper \+ Forced Alignment)                                (Diarization) |

| | |
            v                                                  v |
|
| | |
            \+---------------------\> \<--------------------+ |
                                          (Align & Merge) |

| |
                                                  v |
|
                                            (Text/JSON/SRT) |

This flow shows the .mov file being processed. Its audio is extracted and converted. This single audio file is then fed in parallel to the transcription pipeline (yielding timed words) and the diarization pipeline (yielding timed speaker labels). A final synchronization module merges these two outputs to produce the final, structured transcript.

### **4.2. Toolchain and Dependency Management Plan**

A successful build of this application will require a specific set of system-level tools, development frameworks, and third-party libraries.

* **System-Level Tools (managed via Homebrew)**:
  * **FFmpeg**: An indispensable command-line utility for media manipulation. It will be used by the application's backend to extract and convert the audio tracks from the recorded .mov file into the 16kHz mono WAV format required by the Whisper and pyannote models.58
  * **Python 3**: The runtime environment for the post-processing scripts. It is required to execute pyannote.audio and potentially the whisperx transcription pipeline.
  * **whisper.cpp** (Optional): If the C++ implementation of Whisper is chosen over a CoreML-based solution, it can be installed via Homebrew or compiled from source.89
* **macOS Development Environment**:
  * **Xcode**: The primary integrated development environment for macOS application development.
  * **Swift or Objective-C**: The primary programming languages for the native application shell and capture engine.
  * **Swift Package Manager (SPM)**: The modern dependency manager for integrating native libraries like WhisperKit.
* **Python Dependencies (managed via pip and a requirements.txt file)**:
  * torch: The core machine learning framework dependency for both Whisper and pyannote.audio.
  * pyannote.audio: The speaker diarization library.
  * openai-whisper / whisperx: The transcription libraries.
  * huggingface\_hub: A utility required by pyannote.audio to download the pre-trained models from the Hugging Face model repository.
* **Virtual Audio Driver (for fallback path)**:
  * **BlackHole (2-channel)**: The virtual audio device driver, to be installed via Homebrew, for the legacy audio capture implementation.88

### **4.3. Proposed Development Roadmap**

A phased development approach is recommended to manage complexity and achieve a functional core product quickly before layering on more advanced features.

* **Phase 1: Minimum Viable Product (MVP) \- Audio-Only Capture & Basic Transcription**
  1. **Goal**: To validate the core functionality of recording a meeting's audio and producing an accurate, albeit non-diarized, transcript.
  2. **Steps**:
     * Implement the audio capture engine using the **BlackHole** VAD method. This is the most well-documented and widely understood approach, making it ideal for establishing a baseline.
     * For simplicity in this phase, record both microphone and system audio into a single, mixed-down stereo WAV file. This defers the complexity of multi-track writing.
     * Integrate a high-performance Whisper backend, such as **WhisperKit** or **whisper.cpp**, to process the recorded WAV file after the meeting concludes.
     * Develop a minimal user interface (either command-line or a simple SwiftUI app) with controls to start/stop recording and a view to display the final text transcript.
* **Phase 2: Introduce Speaker Diarization**
  1. **Goal**: To add the critical "who said what" context to the transcript.
  2. **Steps**:
     * Refactor the audio capture engine to record the microphone and system audio streams to **two separate tracks** within a .mov container using AVAssetWriter.
     * Develop the Python-based post-processing script that runs the pyannote.audio pipeline on the mixed audio to generate speaker segments.
     * Implement the synchronization logic described in Section 3.3 to align the word-level timestamps from Whisper with the speaker segments from pyannote.
     * Update the UI to display the transcript with speaker labels and timestamps.
* **Phase 3: Add Video Capture and Compositing**
  1. **Goal**: To incorporate the optional video recording functionality.
  2. **Steps**:
     * Integrate ScreenCaptureKit to allow the user to select and record an application window or an entire display.
     * Add support for webcam capture using AVCaptureSession.
     * Implement the real-time video compositing logic to create a picture-in-picture layout if both screen and webcam are active.
     * Update the AVAssetWriter implementation to include the new, composited video track in the final .mov file.
* **Phase 4: Architectural Refinement and UX Polish**
  1. **Goal**: To modernize the core architecture and enhance the user experience.
  2. **Steps**:
     * Implement the **Core Audio Taps API** as the primary audio capture method for users on supported macOS versions, retaining the BlackHole method as a fallback.
     * Implement the fully programmatic creation and management of all necessary virtual audio devices, completely removing any requirement for the user to interact with the Audio MIDI Setup utility.
     * Develop a full-featured graphical user interface that allows for easy selection of capture sources (audio and video), management of past recordings, and interactive viewing, searching, and editing of the final transcripts.

#### **Works cited**

1. 8 Ways to Record Internal Audio on Mac in 2025 \- Zight, accessed October 21, 2025, [https://zight.com/blog/record-internal-audio-on-mac/](https://zight.com/blog/record-internal-audio-on-mac/)
2. How to Record Internal Audio on Mac? \- Apple Support Communities, accessed October 21, 2025, [https://discussions.apple.com/thread/255288667](https://discussions.apple.com/thread/255288667)
3. An investigation of Inter-Application Audio Routing on the Macintosh OS X operating system. Author: Richard Hallum \- audiosite, accessed October 21, 2025, [http://www.audiosite.org/uploads/4/3/4/3/4343108/inter-appn-audio-osx-1.pdf](http://www.audiosite.org/uploads/4/3/4/3/4343108/inter-appn-audio-osx-1.pdf)
4. OS X: Route audio output to audio input \- Ask Different \- Apple StackExchange, accessed October 21, 2025, [https://apple.stackexchange.com/questions/221980/os-x-route-audio-output-to-audio-input](https://apple.stackexchange.com/questions/221980/os-x-route-audio-output-to-audio-input)
5. Mac OS X virtual audio driver \- Stack Overflow, accessed October 21, 2025, [https://stackoverflow.com/questions/18443621/mac-os-x-virtual-audio-driver](https://stackoverflow.com/questions/18443621/mac-os-x-virtual-audio-driver)
6. Trying to record system audio \- Apple Support Communities, accessed October 21, 2025, [https://discussions.apple.com/thread/254725271](https://discussions.apple.com/thread/254725271)
7. Setting up BlackHole on Mac \- Moody College of Communication ..., accessed October 21, 2025, [https://cloud.wikis.utexas.edu/wiki/spaces/comm/pages/33425619/How+to+set+up+BlackHole+Audio+on+a+Mac](https://cloud.wikis.utexas.edu/wiki/spaces/comm/pages/33425619/How+to+set+up+BlackHole+Audio+on+a+Mac)
8. 8 Ways to Record Internal Audio on Mac \[2025\] \- Movavi Video Editor, accessed October 21, 2025, [https://www.movavi.com/support/how-to/mac/how-to-record-internal-audio-on-mac.html](https://www.movavi.com/support/how-to/mac/how-to-record-internal-audio-on-mac.html)
9. Soundflower for Mac \- Download, accessed October 21, 2025, [https://soundflower.en.softonic.com/mac](https://soundflower.en.softonic.com/mac)
10. mattingalls/Soundflower: MacOS system extension that allows applications to pass audio to other applications. Soundflower works on macOS Catalina. \- GitHub, accessed October 21, 2025, [https://github.com/mattingalls/Soundflower](https://github.com/mattingalls/Soundflower)
11. Download Soundflower for Mac | MacUpdate, accessed October 21, 2025, [https://soundflower.macupdate.com/](https://soundflower.macupdate.com/)
12. BlackHole: Route Audio Between Apps \- Existential Audio, accessed October 21, 2025, [https://existential.audio/blackhole/](https://existential.audio/blackhole/)
13. Blackhole: Home, accessed October 21, 2025, [https://www.blackhole.audio/](https://www.blackhole.audio/)
14. BlackHole \- Free virtual audio driver for macOS \- Vi-Control, accessed October 21, 2025, [https://vi-control.net/community/threads/blackhole-free-virtual-audio-driver-for-macos.118976/](https://vi-control.net/community/threads/blackhole-free-virtual-audio-driver-for-macos.118976/)
15. Download BlackHole for Mac | MacUpdate, accessed October 21, 2025, [https://blackhole.macupdate.com/](https://blackhole.macupdate.com/)
16. How do I record my screen on Mac with sound? \- Apple Support Communities, accessed October 21, 2025, [https://discussions.apple.com/thread/255528772](https://discussions.apple.com/thread/255528772)
17. The best virtual audio device on MacOS \- Loopback 2 \- YouTube, accessed October 21, 2025, [https://www.youtube.com/watch?v=eDIE3vYpOJY](https://www.youtube.com/watch?v=eDIE3vYpOJY)
18. Audio Hijack: Record Any Audio on MacOS \- Rogue Amoeba, accessed October 21, 2025, [https://rogueamoeba.com/audiohijack/](https://rogueamoeba.com/audiohijack/)
19. Aggregate audio interfaces and use outputs into analog mixer \- possible? \- Music, accessed October 21, 2025, [https://music.stackexchange.com/questions/114377/aggregate-audio-interfaces-and-use-outputs-into-analog-mixer-possible](https://music.stackexchange.com/questions/114377/aggregate-audio-interfaces-and-use-outputs-into-analog-mixer-possible)
20. insidegui/AudioCap: Sample code for recording system ... \- GitHub, accessed October 21, 2025, [https://github.com/insidegui/AudioCap](https://github.com/insidegui/AudioCap)
21. Capturing system audio with Core Audio taps | Apple Developer ..., accessed October 21, 2025, [https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps](https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps)
22. AudioTee: capture system audio output on macOS \- Nick Payne @ Strongly Typed Ltd, accessed October 21, 2025, [https://stronglytyped.uk/articles/audiotee-capture-system-audio-output-macos](https://stronglytyped.uk/articles/audiotee-capture-system-audio-output-macos)
23. Mac Desktop-Audio using BlackHole | OBS Forums, accessed October 21, 2025, [https://obsproject.com/forum/resources/mac-desktop-audio-using-blackhole.1191/](https://obsproject.com/forum/resources/mac-desktop-audio-using-blackhole.1191/)
24. AVCaptureScreenInput | Apple Developer Documentation, accessed October 21, 2025, [https://developer.apple.com/documentation/avfoundation/avcapturescreeninput](https://developer.apple.com/documentation/avfoundation/avcapturescreeninput)
25. Technical Q\&A QA1740: How to capture screen activity to a movie file using AV Foundation on OS X 10.7 Lion and later \- Apple Developer, accessed October 21, 2025, [https://developer.apple.com/library/archive/qa/qa1740/\_index.html](https://developer.apple.com/library/archive/qa/qa1740/_index.html)
26. CMSampleBuffer hell \- Color and Timing issues with ScreenCaptureKit and AVAssetWriter : r/swift \- Reddit, accessed October 21, 2025, [https://www.reddit.com/r/swift/comments/158n4c9/cmsamplebuffer\_hell\_color\_and\_timing\_issues\_with/](https://www.reddit.com/r/swift/comments/158n4c9/cmsamplebuffer_hell_color_and_timing_issues_with/)
27. ReplayKit | Apple Developer Documentation, accessed October 21, 2025, [https://developer.apple.com/documentation/ReplayKit](https://developer.apple.com/documentation/ReplayKit)
28. Recording and Streaming Your macOS App | Apple Developer Documentation, accessed October 21, 2025, [https://developer.apple.com/documentation/ReplayKit/recording-and-streaming-your-macos-app](https://developer.apple.com/documentation/ReplayKit/recording-and-streaming-your-macos-app)
29. ReplayKit for Recording Screen and Microphone Audio in iOS Development with Swift, accessed October 21, 2025, [https://medium.com/@ios\_guru/replaykit-for-recording-screen-and-microphone-audio-be7d9dd41b66](https://medium.com/@ios_guru/replaykit-for-recording-screen-and-microphone-audio-be7d9dd41b66)
30. Capture and stream apps on the Mac with ReplayKit | Documentation \- WWDC Notes, accessed October 21, 2025, [https://wwdcnotes.com/documentation/wwdcnotes/wwdc20-10633-capture-and-stream-apps-on-the-mac-with-replaykit/](https://wwdcnotes.com/documentation/wwdcnotes/wwdc20-10633-capture-and-stream-apps-on-the-mac-with-replaykit/)
31. ScreenCaptureKit | Apple Developer Documentation, accessed October 21, 2025, [https://developer.apple.com/documentation/screencapturekit/](https://developer.apple.com/documentation/screencapturekit/)
32. Meet ScreenCaptureKit | Documentation \- WWDC Notes, accessed October 21, 2025, [https://wwdcnotes.com/documentation/wwdcnotes/wwdc22-10156-meet-screencapturekit/](https://wwdcnotes.com/documentation/wwdcnotes/wwdc22-10156-meet-screencapturekit/)
33. Capturing screen content in macOS | Apple Developer Documentation, accessed October 21, 2025, [https://developer.apple.com/documentation/ScreenCaptureKit/capturing-screen-content-in-macos](https://developer.apple.com/documentation/ScreenCaptureKit/capturing-screen-content-in-macos)
34. ScreenCaptureKit mirror a window and display it in a view : r/SwiftUI \- Reddit, accessed October 21, 2025, [https://www.reddit.com/r/SwiftUI/comments/109tbjt/screencapturekit\_mirror\_a\_window\_and\_display\_it/](https://www.reddit.com/r/SwiftUI/comments/109tbjt/screencapturekit_mirror_a_window_and_display_it/)
35. A look at ScreenCaptureKit on macOS Sonoma | Nonstrict, accessed October 21, 2025, [https://nonstrict.eu/blog/2023/a-look-at-screencapturekit-on-macos-sonoma/](https://nonstrict.eu/blog/2023/a-look-at-screencapturekit-on-macos-sonoma/)
36. Recording to disk using ScreenCaptureKit | Nonstrict, accessed October 21, 2025, [https://nonstrict.eu/blog/2023/recording-to-disk-with-screencapturekit/](https://nonstrict.eu/blog/2023/recording-to-disk-with-screencapturekit/)
37. How to use AVAssetReader and AVAssetWriter for multiple tracks (audio and video) simultaneously? \- Stack Overflow, accessed October 21, 2025, [https://stackoverflow.com/questions/5240581/how-to-use-avassetreader-and-avassetwriter-for-multiple-tracks-audio-and-video](https://stackoverflow.com/questions/5240581/how-to-use-avassetreader-and-avassetwriter-for-multiple-tracks-audio-and-video)
38. Is there any way to export video with multiple audio tracks and keep all of them with video : r/premiere \- Reddit, accessed October 21, 2025, [https://www.reddit.com/r/premiere/comments/1b1czn1/is\_there\_any\_way\_to\_export\_video\_with\_multiple/](https://www.reddit.com/r/premiere/comments/1b1czn1/is_there_any_way_to_export_video_with_multiple/)
39. How to import a mov file with multiple audio tracks so that all show up \- LWKS Forum, accessed October 21, 2025, [https://forum.lwks.com/threads/how-to-import-a-mov-file-with-multiple-audio-tracks-so-that-all-show-up.250414/](https://forum.lwks.com/threads/how-to-import-a-mov-file-with-multiple-audio-tracks-so-that-all-show-up.250414/)
40. How to export a single .mov video file with multiple audio tracks embed on the single file so that I can right click on it when playing the video on a video player and select which audio track I want to hear from the video? \- Reddit, accessed October 21, 2025, [https://www.reddit.com/r/editors/comments/1ajj4tv/how\_to\_export\_a\_single\_mov\_video\_file\_with/](https://www.reddit.com/r/editors/comments/1ajj4tv/how_to_export_a_single_mov_video_file_with/)
41. Multichannel files recording // How to read the file? \- Questions \- scsynth, accessed October 21, 2025, [https://scsynth.org/t/multichannel-files-recording-how-to-read-the-file/8998](https://scsynth.org/t/multichannel-files-recording-how-to-read-the-file/8998)
42. iOS: Sample code for simultaneous record and playback \- Stack Overflow, accessed October 21, 2025, [https://stackoverflow.com/questions/7184341/ios-sample-code-for-simultaneous-record-and-playback](https://stackoverflow.com/questions/7184341/ios-sample-code-for-simultaneous-record-and-playback)
43. objective c \- How can I programmatically create a multi-output ..., accessed October 21, 2025, [https://stackoverflow.com/questions/35469569/how-can-i-programmatically-create-a-multi-output-device-in-os-x](https://stackoverflow.com/questions/35469569/how-can-i-programmatically-create-a-multi-output-device-in-os-x)
44. Creating an aggregate device using Core Audio in Objective-C ..., accessed October 21, 2025, [https://gist.github.com/larussverris/5387819a3a7337937084730a86cee073](https://gist.github.com/larussverris/5387819a3a7337937084730a86cee073)
45. Creating Core Audio aggregate devices programmatically | Technology news, reviews of software, applications, devices, and IT stuff around the world, accessed October 21, 2025, [https://www.flyaga.info/creating-core-audio-aggregate-devices-programmatically/](https://www.flyaga.info/creating-core-audio-aggregate-devices-programmatically/)
46. OS X Programmatically Set Default Output Device \- Stack Overflow, accessed October 21, 2025, [https://stackoverflow.com/questions/30178054/os-x-programmatically-set-default-output-device](https://stackoverflow.com/questions/30178054/os-x-programmatically-set-default-output-device)
47. Create an Aggregate Device to combine multiple audio devices \- Apple Support, accessed October 21, 2025, [https://support.apple.com/en-us/102171](https://support.apple.com/en-us/102171)
48. Is sending different tracks into different output devices at the same time are possible? : r/LogicPro \- Reddit, accessed October 21, 2025, [https://www.reddit.com/r/LogicPro/comments/13rduuu/is\_sending\_different\_tracks\_into\_different\_output/](https://www.reddit.com/r/LogicPro/comments/13rduuu/is_sending_different_tracks_into_different_output/)
49. How to exclude input or output channels from an aggregate CoreAudio device?, accessed October 21, 2025, [https://stackoverflow.com/questions/60445512/how-to-exclude-input-or-output-channels-from-an-aggregate-coreaudio-device](https://stackoverflow.com/questions/60445512/how-to-exclude-input-or-output-channels-from-an-aggregate-coreaudio-device)
50. ios Core audio: how to get samples from AudioBuffer with interleaved audio \- Stack Overflow, accessed October 21, 2025, [https://stackoverflow.com/questions/38038822/ios-core-audio-how-to-get-samples-from-audiobuffer-with-interleaved-audio](https://stackoverflow.com/questions/38038822/ios-core-audio-how-to-get-samples-from-audiobuffer-with-interleaved-audio)
51. Audio Buffers | Switchboard Documentation, accessed October 21, 2025, [https://docs.switchboard.audio/audio-buffers/](https://docs.switchboard.audio/audio-buffers/)
52. AVFoundation Quick Start \- Part 1/4, Introduction and Session Setup | by Rafał | Medium, accessed October 21, 2025, [https://medium.com/@rafal.grodzinski/avfoundation-quick-start-part-1-4-introduction-and-session-setup-371897321205](https://medium.com/@rafal.grodzinski/avfoundation-quick-start-part-1-4-introduction-and-session-setup-371897321205)
53. AVCam: Building a camera app | Apple Developer Documentation, accessed October 21, 2025, [https://developer.apple.com/documentation/avfoundation/avcam-building-a-camera-app](https://developer.apple.com/documentation/avfoundation/avcam-building-a-camera-app)
54. Record Video Using MAC Webcam— macOS Swift | by Gayashan Dharmasiri \- Medium, accessed October 21, 2025, [https://medium.com/@kgdharmasiri/record-video-using-your-mac-web-camera-macos-swift-code-ef6f6fedf7df](https://medium.com/@kgdharmasiri/record-video-using-your-mac-web-camera-macos-swift-code-ef6f6fedf7df)
55. How to use the AVFoundation to capture video data in macOS? \- Stack Overflow, accessed October 21, 2025, [https://stackoverflow.com/questions/54009139/how-to-use-the-avfoundation-to-capture-video-data-in-macos](https://stackoverflow.com/questions/54009139/how-to-use-the-avfoundation-to-capture-video-data-in-macos)
56. How To Make Picture-in-Picture Mode for iOS with AVFoundation, accessed October 21, 2025, [https://www.banuba.com/blog/how-to-implement-an-overlay-video-editor-picture-in-picture-mode-for-ios-with-avfoundation](https://www.banuba.com/blog/how-to-implement-an-overlay-video-editor-picture-in-picture-mode-for-ios-with-avfoundation)
57. AVAssetWriter | Apple Developer Documentation, accessed October 21, 2025, [https://developer.apple.com/documentation/avfoundation/avassetwriter](https://developer.apple.com/documentation/avfoundation/avassetwriter)
58. openai/whisper: Robust Speech Recognition via Large-Scale Weak Supervision \- GitHub, accessed October 21, 2025, [https://github.com/openai/whisper](https://github.com/openai/whisper)
59. Whisper (speech recognition system) \- Wikipedia, accessed October 21, 2025, [https://en.wikipedia.org/wiki/Whisper\_(speech\_recognition\_system)](https://en.wikipedia.org/wiki/Whisper_\(speech_recognition_system\))
60. Introducing Whisper \- OpenAI, accessed October 21, 2025, [https://openai.com/index/whisper/](https://openai.com/index/whisper/)
61. Use Whisper on Mac to Transcribe Audio and Video Files Instantly in Terminal \- MacOS Tips, accessed October 21, 2025, [https://macos.gadgethacks.com/how-to/whisper-transcribe-audio-video-terminal-mac/](https://macos.gadgethacks.com/how-to/whisper-transcribe-audio-video-terminal-mac/)
62. Running Whisper on an M1 Mac to transcribe audio data locally \- Dag-Inge Aas, accessed October 21, 2025, [https://www.daginge.com/blog/running-whisper-on-an-m1-mac-to-transcribe-audio-data-locally](https://www.daginge.com/blog/running-whisper-on-an-m1-mac-to-transcribe-audio-data-locally)
63. ggml-org/whisper.cpp: Port of OpenAI's Whisper model in C ... \- GitHub, accessed October 21, 2025, [https://github.com/ggerganov/whisper.cpp](https://github.com/ggerganov/whisper.cpp)
64. vade/OpenAI-Whisper-CoreML \- GitHub, accessed October 21, 2025, [https://github.com/vade/OpenAI-Whisper-CoreML](https://github.com/vade/OpenAI-Whisper-CoreML)
65. argmaxinc/whisperkit-coreml \- Hugging Face, accessed October 21, 2025, [https://huggingface.co/argmaxinc/whisperkit-coreml](https://huggingface.co/argmaxinc/whisperkit-coreml)
66. argmaxinc/WhisperKit: On-device Speech Recognition for Apple Silicon \- GitHub, accessed October 21, 2025, [https://github.com/argmaxinc/WhisperKit](https://github.com/argmaxinc/WhisperKit)
67. Rudrankriyam \- Whisper Kit Sample \- StackBlitz, accessed October 21, 2025, [https://stackblitz.com/github.com/rudrankriyam/WhisperKit-Sample](https://stackblitz.com/github.com/rudrankriyam/WhisperKit-Sample)
68. Whisper Transcription on the App Store, accessed October 21, 2025, [https://apps.apple.com/us/app/whisper-transcription/id1668083311](https://apps.apple.com/us/app/whisper-transcription/id1668083311)
69. Speaker Diarization: Accuracy in Audio Transcription \- FastPix, accessed October 21, 2025, [https://www.fastpix.io/blog/speaker-diarization-libraries-apis-for-developers](https://www.fastpix.io/blog/speaker-diarization-libraries-apis-for-developers)
70. Who's Talking? Speaker Diarization and Emotion Recognition | by Gil Shomron \- Medium, accessed October 21, 2025, [https://medium.com/@gil.shomron/whos-talking-speaker-diarization-and-emotion-recognition-in-radio-3e9623baeb2c](https://medium.com/@gil.shomron/whos-talking-speaker-diarization-and-emotion-recognition-in-radio-3e9623baeb2c)
71. Visualization with pyannote.core \- Colab \- Google, accessed October 21, 2025, [https://colab.research.google.com/github/pyannote/pyannote-audio/blob/develop/tutorials/intro.ipynb](https://colab.research.google.com/github/pyannote/pyannote-audio/blob/develop/tutorials/intro.ipynb)
72. pyannote/pyannote-audio: Neural building blocks for speaker diarization: speech activity detection, speaker change detection, overlapped speech detection, speaker embedding \- GitHub, accessed October 21, 2025, [https://github.com/pyannote/pyannote-audio](https://github.com/pyannote/pyannote-audio)
73. Who spoke when: Choosing the right speaker diarization tool \- ML6, accessed October 21, 2025, [https://www.ml6.eu/en/blog/who-spoke-when-choosing-the-right-speaker-diarization-tool](https://www.ml6.eu/en/blog/who-spoke-when-choosing-the-right-speaker-diarization-tool)
74. pyannote/speaker-diarization \- Hugging Face, accessed October 21, 2025, [https://huggingface.co/pyannote/speaker-diarization](https://huggingface.co/pyannote/speaker-diarization)
75. Whisper and Pyannote: The Ultimate Solution for Speech Transcription, accessed October 21, 2025, [https://scalastic.io/en/whisper-pyannote-ultimate-speech-transcription/](https://scalastic.io/en/whisper-pyannote-ultimate-speech-transcription/)
76. pyannote.audio 2.0 documentation, accessed October 21, 2025, [https://pyannote.github.io/pyannote-audio/](https://pyannote.github.io/pyannote-audio/)
77. Speaker Diarization — NVIDIA NeMo Framework User Guide, accessed October 21, 2025, [https://docs.nvidia.com/nemo-framework/user-guide/latest/nemotoolkit/asr/speaker\_diarization/intro.html](https://docs.nvidia.com/nemo-framework/user-guide/latest/nemotoolkit/asr/speaker_diarization/intro.html)
78. Models — NVIDIA NeMo Framework User Guide, accessed October 21, 2025, [https://docs.nvidia.com/nemo-framework/user-guide/latest/nemotoolkit/asr/speaker\_diarization/models.html](https://docs.nvidia.com/nemo-framework/user-guide/latest/nemotoolkit/asr/speaker_diarization/models.html)
79. speechbrain/speechbrain: A PyTorch-based Speech Toolkit \- GitHub, accessed October 21, 2025, [https://github.com/speechbrain/speechbrain](https://github.com/speechbrain/speechbrain)
80. Speaker Diarization in Python | Picovoice, accessed October 21, 2025, [https://picovoice.ai/blog/speaker-diarization-in-python/](https://picovoice.ai/blog/speaker-diarization-in-python/)
81. Top 8 speaker diarization libraries and APIs in 2025 \- AssemblyAI, accessed October 21, 2025, [https://www.assemblyai.com/blog/top-speaker-diarization-libraries-and-apis](https://www.assemblyai.com/blog/top-speaker-diarization-libraries-and-apis)
82. Best Open source Speech to text+ diarization models : r/LocalLLaMA \- Reddit, accessed October 21, 2025, [https://www.reddit.com/r/LocalLLaMA/comments/1khs34q/best\_open\_source\_speech\_to\_text\_diarization\_models/](https://www.reddit.com/r/LocalLLaMA/comments/1khs34q/best_open_source_speech_to_text_diarization_models/)
83. callstack/ai-meeting-transcription: AI Tool for meeting transcriptions \- GitHub, accessed October 21, 2025, [https://github.com/callstack/ai-meeting-transcription](https://github.com/callstack/ai-meeting-transcription)
84. pyannote/speaker-diarization-3.1 \- Hugging Face, accessed October 21, 2025, [https://huggingface.co/pyannote/speaker-diarization-3.1](https://huggingface.co/pyannote/speaker-diarization-3.1)
85. pyannote.audio 2.1 speaker diarization pipeline: principle, benchmark, and recipe \- ISCA Archive, accessed October 21, 2025, [https://www.isca-archive.org/interspeech\_2023/bredin23\_interspeech.pdf](https://www.isca-archive.org/interspeech_2023/bredin23_interspeech.pdf)
86. Speaker\_Diarization\_Inference.ipynb \- Google Colab, accessed October 21, 2025, [https://colab.research.google.com/github/NVIDIA/NeMo/blob/stable/tutorials/speaker\_tasks/Speaker\_Diarization\_Inference.ipynb](https://colab.research.google.com/github/NVIDIA/NeMo/blob/stable/tutorials/speaker_tasks/Speaker_Diarization_Inference.ipynb)
87. m-bain/whisperX: WhisperX: Automatic Speech ... \- GitHub, accessed October 21, 2025, [https://github.com/m-bain/whisperX](https://github.com/m-bain/whisperX)
88. alexkroman/opennotes: Open Source AI Notetaker for Your Meetings \- GitHub, accessed October 21, 2025, [https://github.com/alexkroman/opennotes](https://github.com/alexkroman/opennotes)
89. lukasbach/pensieve: Desktop app for recording meetings from locally running apps and transcribing and summarizing them with a local LLM \- GitHub, accessed October 21, 2025, [https://github.com/lukasbach/pensieve](https://github.com/lukasbach/pensieve)
