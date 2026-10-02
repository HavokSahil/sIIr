# sIIr — Music Observatory

![sIIr](assets/branding/launcher.svg)

[Android releases](https://github.com/HavokSahil/sIIr/releases) · [Build status](https://github.com/HavokSahil/sIIr/actions)

An Android-focused Flutter workbench for exploring recordings and microphone input. The app opens directly to its disc-based main menu, with no intro video or animation delay.

## Workspace

**Signal → Descriptors → Statistics → Structure → Inspector → Experiments**

The desktop layout has an analysis tree, one active pane and a frame inspector. Phones use section/tool selectors and a graph-first workspace. Details, markers, statistics and inspector controls are in the Analysis details sheet. A compact transport stays visible. The original monochrome palette, Gwendolyne title, ElMessiri headings, Zain body font, layered discs, illustrated controls and rounded analyzer branches are preserved. Numerical readouts use monospace, and statistical heatmaps retain color to explain their values.

Every tool has a **Maths** panel with intuition, formulas, notation and explicit measurement conventions.

- **Signal:** waveform envelope, spectrogram, selected-frame spectrum and native ECQT pitch-class classification.
- **Descriptors:** RMS, centroid, spread, normalized spectral entropy, power flatness, 85% power roll-off, positive spectral flux, zero-crossing rate, chroma, five MFCCs and tempo autocorrelation candidates.
- **Statistics:** Pearson correlation, standardized PCA with loadings/explained variance, interval summary and RMS histogram.
- **Structure:** chroma self-similarity, checkerboard novelty, candidate boundaries and manual section labels.
- **Inspector:** nearest frame values, units, configurable Hann window and hop, actual time/frequency resolution.
- **Experiments:** reanalyze a selected interval with gain; compare measured/predicted RMS and spectral descriptor differences.

## Input and interaction

The synthesized 18-second demo loads when the analyzer opens. Graphs start with a one-second viewport. Waveforms show a smoothed envelope, chroma uses a pitch-class radar, and CQT/MFCC/tempo/RMS distributions use bars. Plot side ornaments are removed; spectrograms use an inferno-style palette with a labeled −100…+40 dB scale. Maths sheets use a monochrome surface. The source selector switches between **Microphone / Live stats** and **Audio file / Windowed stats**. File analysis, playback cursor, pins, annotations and interval are preserved when switching to mic and back. Import PCM WAV directly; Android's MediaExtractor/MediaCodec bridge decodes other supported audio formats. Playback uses the original local recording. Microphone input is analyzed as a rolling four-second buffer, refreshed at most every 180 ms when the previous update has finished; waveform viewing analyzes only the latest second of that buffer; time coordinates are relative to the current analysis buffer and it is not recorded for playback.

Timeline views share a viewport: tap to inspect, drag to pan and use Analysis details to select an interval or add a marker. Spectrum has a separate frequency viewport; PCA has independent two-axis navigation. Use toolbar +/- or pointer-anchored wheel zoom. Drag a nearby pin to reposition it; labels can be edited, deleted or moved to the cursor. Time pins jump playback; frequency pins retain their frame time and frequency.

Keyboard shortcuts: **Space** playback, **+/-** zoom, **I** return to pan, **P** add a marker, **R** reset timeline, **←/→** move the cursor by 0.1 seconds. Touch supports plot dragging and two-finger pinch zoom. Fullscreen animates away the surrounding navigation and enters immersive mode; Back exits fullscreen first. Follow is enabled by default: the time window moves with the file playback cursor instead of squeezing the recording into one plot. Pan disables Follow for free exploration.

JSON export writes an analysis file to the application's documents directory and displays its path. It includes frame features, chroma/MFCC, correlation/PCA, recurrence/novelty, settings, viewports, pins, annotations, interval and gain results. Projects and annotations are session-local; there is no project import or hosted backend.

## Analysis conventions

WAV decoding and analysis run in a persistent worker isolate using `fftea`, separate from playback. FFT setups are reused, MFCC filters skip zero weights, and waveform min/max envelopes are built once in the worker. Playback updates only the graph and transport at 30 Hz; mic viewing uses a 2048-sample minimum hop and omits global statistics unless a Statistics or Structure tool is selected. Mono PCM is resampled to 22,050 Hz with a 48-tap Hann-windowed sinc low-pass filter and 256 fractional phases. Native 22,050 Hz samples bypass resampling. The finite filter has a transition band; it is not an ideal brick-wall filter.

Default STFT: 1,024 samples, 512-sample hop, Hann window. The hop increases automatically to cap analysis at 6,000 frames. Import limits: eight minutes and 100 MB. Self-similarity is capped at 160 uniformly sampled frames; display heatmaps are downsampled to limit painting cost. Edge recordings shorter than a frame are zero padded; incomplete trailing frames are omitted.

Silence produces zero spectral descriptor placeholders, floored MFCC logs, and no tempo candidates. Constant columns have zero correlation and PCA variance. RMS is not calibrated SPL or perceptual loudness; chroma is not chord transcription; tempo and boundary outputs are candidates. The Maths panels document each convention.

The original Essentia JNI bridge is experimental and its beat/onset/pitch functions are stubs. The workbench does not depend on those algorithms. Descriptors use Dart; Android CQT uses vendored ECQT/PFFFT through FFI. Native kernels and buffers stay warm, and CQT is computed only for the displayed cursor (10 Hz maximum), not for the entire file. ECQT starts at C2 with 12 bins/octave; the twelve displayed classes sum squared magnitudes over octaves. It reports pitch-class energy, not a fundamental or chord transcription. See native/ecqt/ORIGIN.md for pinned provenance and correctness fixes.

## Development

The GPU ink path uses current floating-point image APIs; it is tested with
Flutter 3.47.6 (Dart 3.13.5):

```sh
flutter pub get
flutter analyze lib/workbench lib/main.dart lib/core/theme.dart lib/services/mic_controller.dart test
flutter test
flutter run
```

Android builds require an Android SDK, NDK 27.0.12077973 and CMake for the existing JNI target. Other native platforms are not configured in this repository. Audio decoding, playback and microphone behavior require device QA; widget tests mock platform audio channels.

Numerical tests cover FFT/sine measurements, gain invariance, silence/empty input, anti-alias resampling, PCA eigenvector identities, recurrence symmetry and PCM WAV scaling. Widget tests cover desktop navigation/Maths and phone layout. Native tests cover semitone peaks across seven octaves, chord classes, silence and lazy worker pitch. Fullscreen and pinch gestures are covered by widget tests.

### Native validation and benchmark (Linux host)

```sh
cc -O3 -shared -fPIC native/ecqt/shirr_ecqt.c native/ecqt/pffft/pffft.c -lm -o /tmp/libshirr_ecqt.so
SHIRR_ECQT_LIBRARY=/tmp/libshirr_ecqt.so flutter test
dart compile exe tool/benchmark_analysis.dart -o /tmp/shirr-analysis-benchmark
SHIRR_ECQT_LIBRARY=/tmp/libshirr_ecqt.so /tmp/shirr-analysis-benchmark
```

The benchmark compares full ten-second and lightweight one-second waveform workloads, not an end-to-end device FPS measurement. Use profile mode on the phone when assessing animation performance.

## Beat tracking, fluid visualization and cellular music

The **Beat tracking** tool in Structure implements the causal PLP equations (8–9)
from Meier, Chiu & Müller, *A Real-Time Beat Tracking System with Zero Latency and
Enhanced Controllability* (TISMIR 2024), [doi:10.5334/tismir.189](https://doi.org/10.5334/tismir.189).
This is an independent Dart implementation; it uses spectral flux rather than the
paper's trained RNN activation. Signed pulse kernels are overlap-added and local
maxima at an adjustable decision line produce beat triggers. Details expose tempo
bounds, full kernel duration, lookahead and stability threshold. Microphone PCM is
processed once through persistent trailing Hann frames (2048 samples, hop 512);
file analysis uses the existing descriptor frames, timestamped at their end to
remain causal. Computation runs in the analysis isolate. Lookahead is predictive;
phone capture/display latency has not been calibrated, and paper-level accuracy
or zero end-to-end latency is not claimed. The plot follows the shared playback
cursor and includes beat markers, local BPM and stability.

**Visualize** couples a 64 × 96 pressure-projected velocity solver in a worker
isolate to GPU-resident dye feedback. A Flutter fragment shader advects and injects
dye at 512 columns by default, with height matched to the viewport; Balanced (384)
and Ultra (768) are available. Changing quality preserves dye through normalized
texture sampling. Only the small velocity texture is transferred from the CPU;
the full dye texture stays on the GPU using `Picture.toImageSync`, with no pixel
readback during playback. Unsupported shader backends fall back to CPU dye.
The method is inspired by [Jos Stam's Stable Fluids](https://www.josstam.com/publications).
Audio energy controls dye injection; low/high-band energy controls moving forces.
Mic input uses a low-pass/high-pass energy approximation; file input uses STFT
bands and spectral flux at the playback position. Touch injects velocity and dye.
A simple smooth exposure curve keeps ink visible without specular highlights
or bloom. Floating-point velocity and dye textures avoid 8-bit quantization bands.
Audio controls are eased, emitter phase is integrated continuously, and gentle
upward jets replace abrupt orbital impulses. Sensitivity, persistence, clear and fullscreen
controls are available. Rendering
requests are bounded to one in flight on display vsync, with elapsed-time integration and eased audio input. This is an artistic flow
approximation, not a free-surface water simulation. The optional host benchmark
`tool/benchmark_fluid.dart` measures CPU solver cost, not phone or GPU frame rate.

**Music Generation** evolves a 32-cell elementary binary automaton with periodic
boundaries for 64 generations. Rule 30, 90, 110 and 184 are available. Tap the seed
row or randomize it; select a pentatonic/Dorian scale and tempo. New 0→1 transitions
trigger scale pitches, with a deterministic rotating four-voice cap. One generation
is one eighth note. Smooth envelopes shape a two-harmonic additive synthesizer,
rendered off the UI thread to 22,050 Hz mono PCM WAV. Playback, pause, stop, looping,
a synchronized score playhead and WAV export use the rendered audio. The seed and
settings reproduce the same score. [Elementary automata background](https://wolframscience.com/nks/p27--how-do-simple-programs-behave/).

Tests cover regular pulse tracking, silence, causal prefix invariance, predictive
lookahead, PCM chunk-boundary invariance, automaton truth-table/boundary behavior,
deterministic bounded synthesis, WAV duration, fluid fading/finite state, and
narrow-phone layouts with Maths panels. Device testing is still necessary for
microphone permissions, audio output and subjective tracking accuracy.

## Android releases and automation

The GitHub workflow runs static analysis, Dart/widget tests with the native CQT
library, and an Android release build on pushes and pull requests. Tags matching
`v*` publish the universal APK and SHA-256 checksum to GitHub Releases.
Manual workflow runs provide downloadable build artifacts.

Download `sIIr-android.apk` from Releases and install it on Android 7.0/API 24 or
newer. Microphone access is requested when choosing live input. Recordings and
analysis stay local.

Current APKs use the project's development signing configuration. They are
sideload builds, not Play Store releases; CI and local signing keys can differ,
so switching between them may require uninstalling the earlier build. A persistent
production signing key is needed before distributing upgrades through a store.

The Dart package name, Android application ID and native ABI names retain
`shirr` for compatibility. User-facing branding and the repository are **sIIr**.

To publish a version, update `pubspec.yaml` and the menu version, commit the
changes, then push a matching version tag. The release workflow attaches its
validated APK automatically.
