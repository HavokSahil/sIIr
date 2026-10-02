import 'dart:convert';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:shirr/workbench/analysis.dart';
import 'package:shirr/workbench/tools.dart';
import 'package:wav/wav.dart';

AnalysisResult analyze(List<double> samples, {int rate = 22050}) =>
    analyzeAudio({
      'samples': samples,
      'sampleRate': rate,
      'window': 1024,
      'hop': 512,
    });

void main() {
  test('sine wave FFT, RMS, centroid and gain invariance', () {
    const rate = 22050, frequency = rate * 20 / 1024;
    final samples = List.generate(
      rate,
      (i) => 0.4 * sin(2 * pi * frequency * i / rate),
    );
    final before = analyze(samples),
        after = analyze(samples.map((x) => x * 2).toList());
    final f = before.frames[2], g = after.frames[2];
    final peak = f.spectrum.indexOf(f.spectrum.reduce(max));
    expect(peak, 20);
    expect(f.values[0], closeTo(0.4 / sqrt(2), 1e-6));
    expect(f.values[1], closeTo(frequency, 1));
    expect(g.values[0], closeTo(f.values[0] * 2, 1e-10));
    expect(g.values[1], closeTo(f.values[1], 1e-8));
    expect(g.values[4], closeTo(f.values[4], 1e-10));
    expect(f.spectrum.length, 513);
  });
  test(
    'silence, empty input and short recordings remain finite and exportable',
    () {
      for (final samples in [
        <double>[],
        List.filled(50, 0.0),
        List.filled(22050, 0.0),
      ]) {
        final d = analyze(samples);
        for (final frame in d.frames) {
          expect(frame.values.every((x) => x.isFinite), isTrue);
          expect(frame.values, everyElement(0));
          expect(frame.mfcc.every((x) => x.isFinite), isTrue);
        }
        expect(d.tempo, isEmpty);
        expect(d.explained, everyElement(0));
        expect(() => jsonEncode(d.toJson()), returnsNormally);
      }
    },
  );
  test(
    'PCA loadings are orthonormal and explain ordered nonnegative variance',
    () {
      final d = analyze(demoSamples());
      final v = d.loadings;
      double dot(List<double> a, List<double> b) =>
          List.generate(a.length, (i) => a[i] * b[i]).reduce((a, b) => a + b);
      expect(dot(v[0], v[0]), closeTo(1, 1e-9));
      expect(dot(v[0], v[1]), closeTo(0, 1e-9));
      expect(d.explained[0], greaterThanOrEqualTo(d.explained[1]));
      expect(d.explained.reduce((a, b) => a + b), lessThanOrEqualTo(1.000001));
      // Eigenvector equation detects an incorrect rotation even when axes remain orthogonal.
      final trace = List.generate(
        8,
        (i) => d.correlation[i][i],
      ).reduce((a, b) => a + b);
      for (int axis = 0; axis < 2; axis++) {
        for (int i = 0; i < 8; i++) {
          expect(
            dot(d.correlation[i], v[axis]),
            closeTo(d.explained[axis] * trace * v[axis][i], 1e-7),
          );
        }
      }
      for (int i = 0; i < d.similarity.length; i++) {
        expect(d.similarity[i][i], closeTo(1, 1e-9));
        expect(d.similarity[i][0], closeTo(d.similarity[0][i], 1e-9));
      }
    },
  );
  test('resampling suppresses above-Nyquist input and preserves passband', () {
    List<double> tone(double frequency) =>
        List.generate(44100, (i) => 0.4 * sin(2 * pi * frequency * i / 44100));
    final pass = analyze(tone(1000), rate: 44100);
    final stop = analyze(tone(15000), rate: 44100);
    expect(pass.frames[5].values[0], closeTo(0.4 / sqrt(2), 0.003));
    expect(stop.frames[5].values[0], lessThan(0.003));
    expect(pass.sampleRate, 22050);
  });
  test('WAV roundtrip preserves full-scale convention', () {
    final wav = Wav.read(encodeWav([0, 0.5, -0.5, 1, -1], 22050));
    expect(wav.samplesPerSecond, 22050);
    expect(wav.toMono()[1], closeTo(0.5, 0.0001));
    expect(wav.toMono()[2], closeTo(-0.5, 0.0001));
  });
  test('every tool has a mathematical definition and validity convention', () {
    expect(tools.map((t) => t.id).toSet().length, tools.length);
    for (final section in sections) {
      expect(tools.where((t) => t.section == section), isNotEmpty);
    }
    for (final tool in tools) {
      expect(tool.formula, isNotEmpty);
      expect(tool.intuition, isNotEmpty);
      expect(tool.rigor.length, greaterThan(80));
    }
  });
}
