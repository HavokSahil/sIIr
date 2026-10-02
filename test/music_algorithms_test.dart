import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:wav/wav.dart';
import 'package:shirr/music/beat_tracker.dart';
import 'package:shirr/music/cellular_music.dart';
import 'package:shirr/music/fluid.dart';

void main() {
  test(
    'continuous PCM beat tracking is independent of audio chunk boundaries',
    () {
      final samples = List.generate(22050 * 3, (i) {
        final phase = i % 11025;
        return phase < 500
            ? sin(2 * pi * 440 * i / 22050) * exp(-phase / 100)
            : 0.0;
      });
      final whole = BeatAudioStream(22050, const BeatSettings()).add(samples);
      final stream = BeatAudioStream(22050, const BeatSettings());
      BeatTrace trace = BeatTrace.empty;
      for (int i = 0; i < samples.length; i += 777) {
        trace = stream.add(samples.sublist(i, min(i + 777, samples.length)));
      }
      expect(trace.times, whole.times);
      expect(trace.pulse, whole.pulse);
      expect(trace.events, whole.events);
    },
  );
  test(
    'causal PLP locks to a 120 BPM pulse and remains silent on zero input',
    () {
      final tracker = CausalPlp(
        .02,
        const BeatSettings(minBpm: 100, maxBpm: 140),
      );
      final events = <double>[];
      BeatState? state;
      for (int i = 0; i < 600; i++) {
        state = tracker.add(i % 25 == 0 ? 1 : 0, includeContext: i == 599);
        if (state.beat) events.add(i * .02);
      }
      expect(state!.bpm, closeTo(120, 2));
      expect(events.length, greaterThan(15));
      for (int i = 1; i < events.length; i++) {
        expect(events[i] - events[i - 1], closeTo(.5, .04));
      }
      final silent = CausalPlp(.02);
      for (int i = 0; i < 400; i++) {
        final s = silent.add(0);
        expect(s.beat, isFalse);
        expect(s.pulse, 0);
        expect(s.bpm, 0);
      }
    },
  );
  test(
    'PLP prefix is unaffected by future activations; lookahead advances triggers',
    () {
      final times = List.generate(500, (i) => i * .02);
      final values = List.generate(500, (i) => i % 25 == 0 ? 1.0 : 0.0);
      final normal = trackBeats(times, values, .02);
      final prefix = trackBeats(
        times.take(250).toList(),
        values.take(250).toList(),
        .02,
      );
      expect(normal.pulse.take(250).toList(), prefix.pulse);
      final early = trackBeats(
        times,
        values,
        .02,
        const BeatSettings(lookahead: .1),
      );
      for (final event in normal.events.where((t) => t > 3 && t < 9)) {
        expect(
          early.events.any((t) => (t - (event - .1)).abs() <= .04),
          isTrue,
        );
      }
    },
  );
  test(
    'rule 90 is XOR of neighbors, wrap boundary works and score is deterministic',
    () {
      expect(evolveCells([0, 0, 1, 0, 0], 90), [0, 1, 0, 1, 0]);
      expect(evolveCells([1, 0, 0, 0, 0], 90), [0, 1, 0, 0, 1]);
      final seed = List.generate(32, (i) => i == 16 ? 1 : 0);
      final a = cellularScore(seed), b = cellularScore(seed);
      expect(a.rows, b.rows);
      expect(a.notes, b.notes);
      expect(a.notes.every((notes) => notes.length <= 4), isTrue);
      final silence = cellularScore(List.filled(32, 0));
      expect(silence.notes.every((notes) => notes.isEmpty), isTrue);
    },
  );
  test(
    'rendered music is finite, nonzero, bounded and has the specified duration',
    () {
      final bytes = renderCellularWav({
        'seed': List.generate(32, (i) => i == 16 ? 1 : 0),
        'rule': 30,
        'bpm': 120.0,
        'scale': 'Minor pentatonic',
      });
      final wav = Wav.read(bytes);
      final samples = wav.toMono();
      expect(wav.samplesPerSecond, 22050);
      expect(samples.length / 22050, closeTo(16, 1 / 22050));
      expect(samples.every((x) => x.isFinite && x.abs() <= 1), isTrue);
      expect(samples.map((x) => x.abs()).reduce(max), greaterThan(.05));
    },
  );
  test('fluid injection advects finite bounded dye, fades and clears', () {
    final fluid = DyeFluid(width: 24, height: 32);
    fluid.splat(.5, .5, 12, -18, [1, .3, .7]);
    final initial = fluid.red.reduce((a, b) => a + b);
    for (int i = 0; i < 80; i++) {
      fluid.step(1 / 30);
    }
    expect(fluid.red.every((x) => x.isFinite && x >= 0), isTrue);
    expect(fluid.u.every((x) => x.isFinite), isTrue);
    expect(fluid.red.reduce((a, b) => a + b), lessThan(initial));
    expect(fluid.pixels().length, 24 * 32 * 4);
    fluid.clear();
    expect(fluid.red.every((x) => x == 0), isTrue);
  });
}
