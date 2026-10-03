# F-Droid submission

Repository: https://github.com/sIIrsuite/sIIr
Application ID: io.siirsuite.siir
License: Apache-2.0
Version: 1.1.1 (version code 3)

## Build

Use Flutter 3.47.6, Java 17, Android NDK 27.0.12077973 and CMake 3.22.1:

```sh
flutter pub get
flutter build apk --release
```

Output: build/app/outputs/flutter-apk/app-release.apk.

ECQT/PFFFT is compiled from vendored C sources. The old Essentia bridge,
precompiled jniLibs and unused CREPE model have been removed.
Flutter SDK artifacts are toolchain dependencies, not vendored app libraries.

Store metadata lives in fastlane/metadata/android/en-US.
Use pubspec.yaml for versionName/versionCode update checks.

## Before filing

- Verify the tagged source builds in F-Droid's build environment.
- Audit transitive dependencies with F-Droid's scanner.
- Use the v1.1.1 source tag.

The local Android release build and Flutter tests do not replace F-Droid's
scanner and build verification.

## Request for Packaging text

Name: sIIr
Application ID: io.siirsuite.siir
Source: https://github.com/sIIrsuite/sIIr
License: Apache-2.0, with separately licensed fonts and native libraries
Category: Multimedia

sIIr is an offline music observatory for live microphone input and audio files.
It provides spectral analysis, ECQT pitch classes, causal PLP beat tracking,
interactive plots and mathematical explanations, plus reactive ink visualization
and cellular-automata music generation.

Native ECQT builds from source. Store descriptions, icon, screenshots and
changelogs are available in the repository's fastlane metadata.

Request packaging review at:
https://gitlab.com/fdroid/rfp/-/issues/new
