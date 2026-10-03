<div align="center">
  <img src="assets/branding/launcher.svg" width="112" alt="sIIr logo">

  <h1>sIIr</h1>
  <p>A music observatory for the curious.</p>

  <a href="https://github.com/sIIrsuite/sIIr/releases/latest">Download Android APK</a>
  ·
  <a href="https://github.com/sIIrsuite/sIIr/actions">Builds</a>
</div>

---

Explore sound, watch it flow, and grow music from simple rules. Built with Flutter, with a monochrome interface and the mathematics behind every tool.

| Analyze | Visualize | Generate |
| :--- | :--- | :--- |
| Live microphone or audio files | Colorful, music-reactive ink | Cellular-automata composition |
| Spectrograms, native ECQT pitch classes and beat tracking | Touch to stir; explore fullscreen | Edit seeds, rules, scales and tempo |
| Descriptors, correlation and PCA | Adjustable sensitivity and persistence | Play, loop and export WAV |

**Inside the analyzer**

Signal → Descriptors → Statistics → Structure → Inspector → Experiments

Follow the playback cursor, zoom into plots, mark moments and open **Maths** for intuition and rigorous explanations. Audio and analysis stay on your device.

## Install

Download `sIIr-android.apk` from the [latest release](https://github.com/sIIrsuite/sIIr/releases/latest). Requires **Android 7.0+**.

APKs currently use development signing. Switching between local and CI builds may require uninstalling the previous version.

## Develop

Flutter **3.47.6**, Java **17**, Android SDK, NDK **27.0.12077973** and CMake **3.22.1**.

```sh
flutter pub get
flutter run
```

```sh
flutter analyze
flutter test
flutter build apk --release
```

GitHub Actions validates changes and builds Android APKs. Version tags (`v*`) publish releases with SHA-256 checksums.

## Under the hood

[ECQT](https://github.com/havoksahil/ecqt) for pitch classes · [Causal PLP](https://doi.org/10.5334/tismir.189) for beat tracking · [Stable Fluids](https://www.josstam.com/publications) for ink · [Elementary cellular automata](https://wolframscience.com/nks/p27--how-do-simple-programs-behave/) for music.

Beat tracking uses spectral flux instead of the paper’s trained activation model. Fluid motion is experimental and still being refined.
