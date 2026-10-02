import 'dart:math';
import 'dart:typed_data';

const musicScales = <String, List<int>>{
  'Minor pentatonic': [0, 3, 5, 7, 10],
  'Major pentatonic': [0, 2, 4, 7, 9],
  'Dorian': [0, 2, 3, 5, 7, 9, 10],
};

List<int> evolveCells(List<int> row, int rule) =>
    List.generate(row.length, (i) {
      final neighborhood =
          row[(i - 1 + row.length) % row.length] * 4 +
          row[i] * 2 +
          row[(i + 1) % row.length];
      return (rule >> neighborhood) & 1;
    });

class CellularScore {
  final List<List<int>> rows;
  final List<List<int>> notes;
  final double stepSeconds;
  const CellularScore(this.rows, this.notes, this.stepSeconds);
  double get duration => rows.length * stepSeconds;
}

CellularScore cellularScore(
  List<int> seed, {
  int rule = 30,
  int steps = 64,
  double bpm = 110,
  String scale = 'Minor pentatonic',
  int root = 48,
}) {
  if (seed.isEmpty || bpm <= 0 || rule < 0 || rule > 255) {
    throw ArgumentError('Invalid automaton settings');
  }
  final intervals = musicScales[scale]!;
  var row = List<int>.of(seed);
  final rows = <List<int>>[], notes = <List<int>>[];
  for (int step = 0; step < steps; step++) {
    rows.add(row);
    final pitches = <int>{};
    // Newly activated cells trigger notes; sustained cells do not retrigger.
    final previous = step == 0 ? List.filled(row.length, 0) : rows[step - 1];
    for (int i = 0; i < row.length; i++) {
      if (row[i] == 1 && previous[i] == 0) {
        final degree = i ~/ 2;
        pitches.add(
          root +
              intervals[degree % intervals.length] +
              12 * (degree ~/ intervals.length),
        );
      }
    }
    // Rotate the voicing to avoid always favoring the low register. Max 4 voices.
    final candidates = pitches.toList();
    notes.add([
      for (int j = 0; j < min(4, candidates.length); j++)
        candidates[(j + step) % candidates.length],
    ]);
    row = evolveCells(row, rule);
  }
  return CellularScore(
    rows,
    notes,
    30 / bpm,
  ); // One generation per eighth note.
}

/// Render in an isolate. Smooth attack/release, bounded four-voice gain and
/// continuous per-note phase avoid clicks and digital clipping.
Uint8List renderCellularWav(Map<String, Object> options) {
  final score = cellularScore(
    options['seed'] as List<int>,
    rule: options['rule'] as int,
    bpm: options['bpm'] as double,
    scale: options['scale'] as String,
  );
  const rate = 22050;
  final samples = Float32List((score.duration * rate).ceil());
  final stepLength = (score.stepSeconds * rate).round();
  for (int step = 0; step < score.notes.length; step++) {
    final start = (step * score.stepSeconds * rate).round();
    for (final midi in score.notes[step]) {
      final frequency = 440 * pow(2, (midi - 69) / 12);
      for (int j = 0; j < stepLength && start + j < samples.length; j++) {
        final t = j / rate, progress = j / stepLength;
        final envelope =
            min(1.0, t / .008) *
            min(1.0, (1 - progress) * score.stepSeconds / .035) *
            exp(-progress * 2.2);
        samples[start + j] +=
            .13 *
            envelope *
            (sin(2 * pi * frequency * t) + .25 * sin(4 * pi * frequency * t)) /
            1.25;
      }
    }
  }
  final bytes = ByteData(44 + samples.length * 2);
  void ascii(int offset, String text) {
    for (int i = 0; i < text.length; i++) {
      bytes.setUint8(offset + i, text.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  bytes.setUint32(4, bytes.lengthInBytes - 8, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  bytes.setUint32(16, 16, Endian.little);
  bytes.setUint16(20, 1, Endian.little);
  bytes.setUint16(22, 1, Endian.little);
  bytes.setUint32(24, rate, Endian.little);
  bytes.setUint32(28, rate * 2, Endian.little);
  bytes.setUint16(32, 2, Endian.little);
  bytes.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  bytes.setUint32(40, samples.length * 2, Endian.little);
  for (int i = 0; i < samples.length; i++) {
    bytes.setInt16(
      44 + i * 2,
      (samples[i].clamp(-1.0, 1.0) * 32767).round(),
      Endian.little,
    );
  }
  return bytes.buffer.asUint8List();
}
