# Tool Evaluations

Record of tools and technologies considered for the project, including rationale for adoption or rejection.

---

## SAM-Audio (Meta)

**Date evaluated**: 2025-01-13
**Decision**: Not adopted
**Status**: May revisit if requirements change

### What it is

SAM-Audio is Meta's foundation model for audio source separation. It isolates specific sounds from audio mixtures using text, visual, or temporal prompts (e.g., "separate the man speaking from background noise").

- Repository: https://github.com/facebookresearch/sam-audio
- Project page: https://ai.meta.com/samaudio/

### Potential use case

Preprocessing step to clean audio before transcription:
- Isolate speech from background noise
- Separate overlapping speakers

### Why we decided not to use it

1. **Not a transcription tool** - SAM-Audio separates audio sources but doesn't transcribe. We'd still need WhisperKit for speech-to-text.

2. **Infrastructure mismatch** - Requires Python + CUDA GPU. Not suitable for on-device iOS processing; would require a server-side pipeline.

3. **Complexity vs. benefit** - WhisperKit handles moderate noise reasonably well. The added infrastructure complexity isn't justified for typical meeting recordings.

4. **Scope creep** - Adding a server component for audio preprocessing is outside our current on-device architecture.

### When to revisit

- If users report significant issues with noisy environments
- If we add server-side processing for other reasons
- If a CoreML/iOS-compatible version becomes available
