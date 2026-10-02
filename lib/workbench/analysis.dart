import 'dart:math';
import 'dart:typed_data';
import 'package:fftea/fftea.dart';
import 'native_cqt.dart';
import '../music/beat_tracker.dart';

NativeCqt? _cqt;
final _fftCache = <int, FFT>{};

const featureNames = [
  'rms',
  'centroid',
  'spread',
  'entropy',
  'flatness',
  'rolloff',
  'flux',
  'zcr',
];

class AnalysisFrame {
  final double time;
  final List<double> spectrum, chroma, mfcc, values;
  AnalysisFrame(this.time, this.spectrum, this.chroma, this.mfcc, this.values);
  List<double> cqt = const [];
  double feature(String id) => values[featureNames.indexOf(id)];
}

class AnalysisResult {
  BeatTrace beats = BeatTrace.empty;
  final List<double> samples;
  final int sampleRate, window, hop;
  final List<AnalysisFrame> frames;
  final List<List<double>> correlation, scores, loadings, similarity;
  final List<double> explained, novelty, structureTimes;
  final List<double> boundaries;
  final List<List<double>> tempo;
  AnalysisResult(
    this.samples,
    this.sampleRate,
    this.window,
    this.hop,
    this.frames,
    this.correlation,
    this.scores,
    this.loadings,
    this.explained,
    this.similarity,
    this.novelty,
    this.structureTimes,
    this.boundaries,
    this.tempo,
  );
  late final List<double> envelopeLow = _envelope(false);
  late final List<double> envelopeHigh = _envelope(true);
  List<double> _envelope(bool upper) {
    const block = 64;
    return List.generate((samples.length / block).ceil(), (i) {
      double v = samples[i * block];
      for (
        int j = i * block + 1;
        j < min(samples.length, (i + 1) * block);
        j++
      ) {
        v = upper ? max(v, samples[j]) : min(v, samples[j]);
      }
      return v;
    });
  }

  double get duration => samples.length / sampleRate;
  int nearest(double t) =>
      frames.isEmpty
          ? 0
          : ((t * sampleRate - window / 2) / hop).round().clamp(
            0,
            frames.length - 1,
          );
  Map<String, dynamic> toJson() => {
    'schema': 'shirr.observatory.v1',
    'settings': {
      'sampleRate': sampleRate,
      'window': window,
      'hop': hop,
      'windowFunction': 'Hann',
      'resampler':
          '48-tap Hann-windowed sinc, 256 phases, cutoff 0.475 × min(1, outputRate/inputRate)',
      'channels': 1,
      'rolloff': 0.85,
    },
    'duration': duration,
    'featureOrder': featureNames,
    'frames':
        frames
            .map(
              (f) => {
                'time': f.time,
                'values': f.values,
                'chroma': f.chroma,
                'mfcc': f.mfcc,
              },
            )
            .toList(),
    'correlation': correlation,
    'pca': {'scores': scores, 'loadings': loadings, 'explained': explained},
    'structure': {
      'times': structureTimes,
      'similarity': similarity,
      'novelty': novelty,
      'candidateBoundaries': boundaries,
    },
    'tempoCandidates': tempo,
    'beats': beats.toJson(),
  };
}

AnalysisResult analyzeAudio(Map<String, dynamic> request) {
  final input = List<double>.from(request['samples'] as List);
  final sourceRate = request['sampleRate'] as int;
  const rate = 22050;
  if (sourceRate <= 0) throw ArgumentError('Sample rate must be positive');
  final length = (input.length * rate / sourceRate).floor();
  final samples = _resample(input, sourceRate, rate);
  final n = request['window'] as int? ?? 1024;
  final requestedHop = request['hop'] as int? ?? 512;
  if (![512, 1024, 2048].contains(n) || requestedHop <= 0) {
    throw ArgumentError('Unsupported frame length or hop');
  }
  final hop = max(requestedHop, (max(0, length - n) / 5999).ceil());
  final fft = _fftCache.putIfAbsent(n, () => FFT(n));
  final cqt = request['cqt'] == true ? (_cqt ??= NativeCqt()) : null;
  final win = List.generate(n, (i) => 0.5 - 0.5 * cos(2 * pi * i / (n - 1)));
  final bins = n ~/ 2 + 1;
  double mel(double f) => 2595 * log(1 + f / 700) / ln10;
  final melEdges = List.generate(
    28,
    (i) => 700 * (pow(10, mel(rate / 2) * i / 27 / 2595) - 1),
  );
  final filters = List.generate(
    26,
    (b) => List.generate(bins, (k) {
      final f = k * rate / n;
      return max(
        0.0,
        min(
          (f - melEdges[b]) / (melEdges[b + 1] - melEdges[b]),
          (melEdges[b + 2] - f) / (melEdges[b + 2] - melEdges[b + 1]),
        ),
      );
    }),
  );
  final sparseFilters =
      filters
          .map(
            (filter) => [
              for (int k = 0; k < filter.length; k++)
                if (filter[k] > 0) (k, filter[k]),
            ],
          )
          .toList();
  final frames = <AnalysisFrame>[];
  List<double>? previous;
  for (int start = 0; start < length; start += hop) {
    if (start > 0 && start + n > length && frames.isNotEmpty) break;
    final raw = List.generate(
      n,
      (i) => start + i < length ? samples[start + i] : 0.0,
    );
    final complex = fft.realFft(List.generate(n, (i) => raw[i] * win[i]));
    final a = List.generate(
      bins,
      (k) => sqrt(complex[k].x * complex[k].x + complex[k].y * complex[k].y),
    );
    final p = a.map((v) => v * v).toList();
    final sumA = a.fold(0.0, (s, v) => s + v);
    final sumP = p.fold(0.0, (s, v) => s + v);
    final silent = sumP < 1e-24;
    final norm = a.map((v) => sumA > 1e-12 ? v / sumA : 0.0).toList();
    double centroid = 0,
        spread = 0,
        entropy = 0,
        flatness = 0,
        rolloff = 0,
        flux = 0;
    if (!silent) {
      for (int k = 0; k < bins; k++) {
        centroid += k * rate / n * norm[k];
      }
      double cumulative = 0;
      bool found = false;
      for (int k = 0; k < bins; k++) {
        spread += pow(k * rate / n - centroid, 2) * norm[k];
        final probability = p[k] / sumP;
        if (probability > 0) {
          entropy -= probability * log(probability) / log(bins);
        }
        cumulative += p[k];
        if (!found && cumulative >= sumP * 0.85) {
          rolloff = k * rate / n;
          found = true;
        }
      }
      spread = sqrt(spread);
      flatness = (exp(p.fold(0.0, (s, v) => s + log(max(v, 1e-24))) / bins) /
              (sumP / bins))
          .clamp(0.0, 1.0);
    }
    if (previous != null) {
      for (int k = 0; k < bins; k++) {
        flux += pow(max(0, norm[k] - previous[k]), 2);
      }
      flux = sqrt(flux);
    }
    previous = norm;
    final rms = sqrt(raw.fold(0.0, (s, v) => s + v * v) / n);
    int crossings = 0;
    for (int i = 1; i < n; i++) {
      if ((raw[i] >= 0) != (raw[i - 1] >= 0)) crossings++;
    }
    final chroma = List.filled(12, 0.0);
    for (int k = 1; k < bins; k++) {
      final f = k * rate / n;
      if (f < 27.5 || f > 4186) continue;
      final note = (69 + 12 * log(f / 440) / ln2).round();
      chroma[note % 12] += a[k];
    }
    final sumC = chroma.fold(0.0, (s, v) => s + v);
    if (sumC > 1e-12) {
      for (int i = 0; i < 12; i++) {
        chroma[i] /= sumC;
      }
    }
    final energies =
        sparseFilters.map((filter) {
          double e = 0;
          for (final weight in filter) {
            e += p[weight.$1] * weight.$2;
          }
          return log(max(e, 1e-24));
        }).toList();
    final mfcc = List.generate(5, (j) {
      double c = 0;
      for (int b = 0; b < 26; b++) {
        c += energies[b] * cos(pi * j * (b + 0.5) / 26);
      }
      return c;
    });
    frames.add(
      AnalysisFrame(
        min((start + n / 2) / rate, length / rate),
        a,
        chroma,
        mfcc,
        [
          rms,
          centroid,
          spread,
          entropy,
          flatness,
          rolloff,
          flux,
          crossings / (n - 1),
        ],
      ),
    );
  }
  if (cqt != null) {
    // Pitch analysis at 10 Hz; reuse each result for nearby descriptor frames.
    List<double> bins = const [];
    double last = -1;
    final pitchFrames =
        request['lightweight'] == true && frames.isNotEmpty
            ? [frames.last]
            : frames;
    for (final frame in pitchFrames) {
      if (frame.time - last >= .1) {
        bins = cqt.transform(samples, (frame.time * rate).round());
        last = frame.time;
      }
      frame.cqt = bins;
    }
  }
  if (request['lightweight'] == true) {
    final result = AnalysisResult(
      samples,
      rate,
      n,
      hop,
      frames,
      List.generate(8, (_) => List.filled(8, 0.0)),
      const [],
      const [],
      const [],
      const [],
      const [],
      const [],
      const [],
      const [],
    );
    if (request['beat'] == true) result.beats = beatAnalysis(result);
    result.envelopeLow;
    result.envelopeHigh;
    return result;
  }
  final m = frames.length;
  final means = List.generate(
    8,
    (j) => m == 0 ? 0.0 : frames.fold(0.0, (s, f) => s + f.values[j]) / m,
  );
  final sd = List.generate(
    8,
    (j) =>
        m < 2
            ? 0.0
            : sqrt(
              frames.fold(0.0, (s, f) => s + pow(f.values[j] - means[j], 2)) /
                  (m - 1),
            ),
  );
  final z =
      frames
          .map(
            (f) => List.generate(
              8,
              (j) => sd[j] < 1e-12 ? 0.0 : (f.values[j] - means[j]) / sd[j],
            ),
          )
          .toList();
  final corr = List.generate(
    8,
    (i) => List.generate(
      8,
      (j) =>
          m < 2 ? 0.0 : z.fold(0.0, (s, row) => s + row[i] * row[j]) / (m - 1),
    ),
  );
  final eigen = _eigen(corr);
  final order = List.generate(8, (i) => i)
    ..sort((a, b) => eigen.$1[b].compareTo(eigen.$1[a]));
  final loadings = List.generate(
    2,
    (c) => List.generate(8, (j) => eigen.$2[j][order[c]]),
  );
  final scores =
      z
          .map(
            (row) => List.generate(2, (c) {
              double sum = 0;
              for (int j = 0; j < 8; j++) {
                sum += row[j] * loadings[c][j];
              }
              return sum;
            }),
          )
          .toList();
  final trace = eigen.$1.fold(0.0, (s, v) => s + max(0, v));
  final explained = List.generate(
    2,
    (c) => trace < 1e-12 ? 0.0 : max(0.0, eigen.$1[order[c]]) / trace,
  );
  final indices = List.generate(
    min(160, m),
    (i) => m <= 160 ? i : (i * (m - 1) / 159).round(),
  );
  final similarity =
      indices
          .map(
            (i) =>
                indices.map((j) {
                  double dot = 0, aa = 0, bb = 0;
                  for (int c = 0; c < 12; c++) {
                    dot += frames[i].chroma[c] * frames[j].chroma[c];
                    aa += pow(frames[i].chroma[c], 2);
                    bb += pow(frames[j].chroma[c], 2);
                  }
                  return aa * bb < 1e-24
                      ? 0.0
                      : (dot / sqrt(aa * bb)).clamp(0.0, 1.0);
                }).toList(),
          )
          .toList();
  final times = indices.map((i) => frames[i].time).toList();
  final novelty = List.filled(indices.length, 0.0);
  for (int t = 4; t + 4 < indices.length; t++) {
    double before = 0, after = 0, cross = 0;
    for (int i = 0; i < 4; i++) {
      for (int j = 0; j < 4; j++) {
        before += similarity[t - 4 + i][t - 4 + j];
        after += similarity[t + i][t + j];
        cross += similarity[t - 4 + i][t + j];
      }
    }
    novelty[t] = max(0.0, (before + after - 2 * cross) / 16);
  }
  final meanN =
      novelty.isEmpty
          ? 0.0
          : novelty.fold(0.0, (s, v) => s + v) / novelty.length;
  final sdN =
      novelty.isEmpty
          ? 0.0
          : sqrt(
            novelty.fold(0.0, (s, v) => s + pow(v - meanN, 2)) / novelty.length,
          );
  final boundaries = <double>[];
  for (int i = 1; i + 1 < novelty.length; i++) {
    if (novelty[i] > meanN + sdN &&
        novelty[i] > novelty[i - 1] &&
        novelty[i] >= novelty[i + 1] &&
        (boundaries.isEmpty || times[i] - boundaries.last >= 1)) {
      boundaries.add(times[i]);
    }
  }
  final tempo = <List<double>>[];
  final energy = frames.fold(0.0, (s, f) => s + f.values[6] * f.values[6]);
  if (energy > 1e-12) {
    for (
      int lag = max(1, (60 * rate / hop / 240).ceil());
      lag <= min(m - 1, (60 * rate / hop / 40).floor());
      lag++
    ) {
      double ac = 0;
      for (int i = 0; i + lag < m; i++) {
        ac += frames[i].values[6] * frames[i + lag].values[6];
      }
      tempo.add([60 * rate / hop / lag, ac / energy]);
    }
  }
  final result = AnalysisResult(
    samples,
    rate,
    n,
    hop,
    frames,
    corr,
    scores,
    loadings,
    explained,
    similarity,
    novelty,
    times,
    boundaries,
    tempo,
  );
  if (request['beat'] == true) result.beats = beatAnalysis(result);
  result.envelopeLow;
  result.envelopeHigh;
  return result;
}

(List<double>, List<List<double>>) _eigen(List<List<double>> matrix) {
  final a = matrix.map((row) => List<double>.from(row)).toList();
  final v = List.generate(
    8,
    (i) => List.generate(8, (j) => i == j ? 1.0 : 0.0),
  );
  for (int iteration = 0; iteration < 256; iteration++) {
    int p = 0, q = 1;
    for (int i = 0; i < 8; i++) {
      for (int j = i + 1; j < 8; j++) {
        if (a[i][j].abs() > a[p][q].abs()) {
          p = i;
          q = j;
        }
      }
    }
    if (a[p][q].abs() < 1e-10) break;
    final angle = 0.5 * atan2(2 * a[p][q], a[q][q] - a[p][p]);
    final c = cos(angle), s = sin(angle);
    final app = a[p][p], aqq = a[q][q], apq = a[p][q];
    for (int k = 0; k < 8; k++) {
      if (k != p && k != q) {
        final kp = a[k][p], kq = a[k][q];
        a[k][p] = a[p][k] = c * kp - s * kq;
        a[k][q] = a[q][k] = s * kp + c * kq;
      }
      final vp = v[k][p], vq = v[k][q];
      v[k][p] = c * vp - s * vq;
      v[k][q] = s * vp + c * vq;
    }
    a[p][p] = c * c * app - 2 * s * c * apq + s * s * aqq;
    a[q][q] = s * s * app + 2 * s * c * apq + c * c * aqq;
    a[p][q] = a[q][p] = 0;
  }
  return (List.generate(8, (i) => a[i][i]), v);
}

List<double> demoSamples() => List.generate(22050 * 18, (i) {
  final t = i / 22050;
  final section = (t / 6).floor();
  final base = [220.0, 261.6256, 329.6276][section.clamp(0, 2)];
  final pulse = exp(-((t * 2) % 1) * 9);
  return 0.22 * sin(2 * pi * base * t) +
      0.1 * sin(2 * pi * base * 1.5 * t) +
      0.16 * pulse * sin(2 * pi * 70 * t);
});

Uint8List encodeWav(List<double> samples, int rate) {
  final data = ByteData(44 + samples.length * 2);
  void tag(int offset, String s) {
    for (int i = 0; i < s.length; i++) {
      data.setUint8(offset + i, s.codeUnitAt(i));
    }
  }

  tag(0, 'RIFF');
  data.setUint32(4, data.lengthInBytes - 8, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, rate, Endian.little);
  data.setUint32(28, rate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  tag(36, 'data');
  data.setUint32(40, samples.length * 2, Endian.little);
  for (int i = 0; i < samples.length; i++) {
    data.setInt16(
      44 + 2 * i,
      (samples[i].clamp(-1.0, 1.0) * 32767).round(),
      Endian.little,
    );
  }
  return data.buffer.asUint8List();
}

// Polyphase windowed-sinc low-pass interpolation. Edge indices are clamped;
// finite filter length means the transition band is not an ideal brick wall.
List<double> _resample(List<double> input, int sourceRate, int targetRate) {
  if (input.isEmpty) return [];
  if (sourceRate == targetRate) return input;
  const taps = 48, phases = 256;
  final cutoff = 0.475 * min(1.0, targetRate / sourceRate);
  final kernels = List.generate(phases, (phase) {
    final weights = List.generate(taps, (tap) {
      final distance = tap - (taps ~/ 2 - 1) - phase / phases;
      final sinc =
          distance.abs() < 1e-12
              ? 2 * cutoff
              : sin(2 * pi * cutoff * distance) / (pi * distance);
      return sinc * (0.5 + 0.5 * cos(pi * distance / (taps / 2)));
    });
    final sum = weights.reduce((a, b) => a + b);
    return weights.map((w) => w / sum).toList();
  });
  return List.generate((input.length * targetRate / sourceRate).floor(), (i) {
    final position = i * sourceRate / targetRate;
    final center = position.floor();
    final phase = ((position - center) * phases).floor().clamp(0, phases - 1);
    double result = 0;
    for (int tap = 0; tap < taps; tap++) {
      final index = (center + tap - (taps ~/ 2 - 1)).clamp(0, input.length - 1);
      result += input[index] * kernels[phase][tap];
    }
    return result;
  });
}

BeatTrace beatAnalysis(
  AnalysisResult data, [
  BeatSettings settings = const BeatSettings(),
]) => trackBeats(
  data.frames.map((f) => f.time + data.window / 2 / data.sampleRate).toList(),
  data.frames.map((f) => f.values[6]).toList(),
  data.hop / data.sampleRate,
  settings,
);
