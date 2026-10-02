import 'dart:math';
import 'dart:io';
import 'package:shirr/workbench/analysis.dart';
import 'package:shirr/workbench/native_cqt.dart';

void main() {
  final input = demoSamples().take(22050 * 10).toList();
  final live = input.sublist(input.length - 22050);
  for (final entry in [
    ('full 10s workload', input, 512, false),
    ('live waveform 1s workload', live, 2048, true),
  ]) {
    final request = {
      'samples': entry.$2,
      'sampleRate': 22050,
      'hop': entry.$3,
      'lightweight': entry.$4,
    };
    analyzeAudio(request);
    final clock = Stopwatch()..start();
    const runs = 20;
    for (int i = 0; i < runs; i++) {
      analyzeAudio(request);
    }
    stdout.writeln(
      '${entry.$1}: ${(clock.elapsedMicroseconds / runs / 1000).toStringAsFixed(2)} ms',
    );
  }
  final cqt = NativeCqt();
  final tone = List.generate(22050, (i) => sin(2 * pi * 440 * i / 22050));
  cqt.transform(tone, 11025);
  final clock = Stopwatch()..start();
  for (int i = 0; i < 100; i++) {
    cqt.transform(tone, 11025);
  }
  stdout.writeln(
    'ECQT warm transform + FFI copy: ${(clock.elapsedMicroseconds / 100000).toStringAsFixed(2)} ms',
  );
  cqt.dispose();
}
