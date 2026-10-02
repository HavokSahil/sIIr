import 'dart:io';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:shirr/workbench/native_cqt.dart';
import 'package:shirr/workbench/analysis_worker.dart';

void main() {
  final available = Platform.environment.containsKey('SHIRR_ECQT_LIBRARY');
  test(
    'native ECQT resolves semitones, chord classes and silence',
    () {
      final cqt = NativeCqt();
      addTearDown(cqt.dispose);
      for (final note in [36, 48, 60, 69, 72, 84, 96]) {
        final frequency = 440 * pow(2, (note - 69) / 12);
        final input = List.generate(
          22050,
          (i) => .4 * sin(2 * pi * frequency * i / 22050),
        );
        final bins = cqt.transform(input, 11025);
        expect(bins.indexOf(bins.reduce(max)) + 36, note);
      }
      final chord = List.generate(
        22050,
        (i) => [60, 64, 67].fold(
          0.0,
          (s, n) =>
              s + .2 * sin(2 * pi * 440 * pow(2, (n - 69) / 12) * i / 22050),
        ),
      );
      final bins = cqt.transform(chord, 11025);
      final classes = List.filled(12, 0.0);
      for (int i = 0; i < bins.length; i++) {
        classes[i % 12] += bins[i] * bins[i];
      }
      final order = List.generate(12, (i) => i)
        ..sort((a, b) => classes[b].compareTo(classes[a]));
      expect(order.take(3).toSet(), {0, 4, 7});
      expect(cqt.transform(List.filled(22050, 0), 11025), everyElement(0));
    },
    skip:
        !available
            ? 'Build the native host library and set SHIRR_ECQT_LIBRARY'
            : false,
  );

  test('worker retains file PCM for lazy cursor-based native pitch', () async {
    final worker = AnalysisWorker();
    addTearDown(worker.dispose);
    await worker.analyze({
      'samples': List.generate(
        22050,
        (i) => .4 * sin(2 * pi * 440 * i / 22050),
      ),
      'sampleRate': 22050,
      'source': 'file',
    });
    final bins = await worker.pitch(.5);
    expect(bins.indexOf(bins.reduce(max)) + 36, 69);
  }, skip: !available ? 'Requires native host library' : false);
}
