import 'dart:math';
import 'package:fftea/fftea.dart';

final _beatFft = FFT(2048);
final _beatWindow = List.generate(
  2048,
  (i) => .5 - .5 * cos(2 * pi * i / 2047),
);

/// Independent Dart implementation of the causal PLP equations (8–9) in
/// Meier, Chiu & Müller, TISMIR 2024, doi:10.5334/tismir.189.
/// Activation is spectral flux, not the paper's trained RNN front end.
class BeatSettings {
  final double minBpm, maxBpm, kernelSeconds, lookahead, threshold;
  const BeatSettings({
    this.minBpm = 60,
    this.maxBpm = 180,
    this.kernelSeconds = 6,
    this.lookahead = 0,
    this.threshold = .08,
  });
}

class BeatState {
  final double pulse, bpm, stability;
  final bool beat;
  final List<double> context;
  const BeatState(
    this.pulse,
    this.bpm,
    this.stability,
    this.beat,
    this.context,
  );
}

class CausalPlp {
  final double period;
  final BeatSettings settings;
  late final int half;
  late final List<double> activation, pulse, window, tempi;
  late final List<List<double>> cosines, sines;
  int count = 0;
  double lastBeat = -100, bpm = 0;
  CausalPlp(this.period, [this.settings = const BeatSettings()]) {
    half = max(2, (settings.kernelSeconds / period / 2).round());
    activation = List.filled(half + 1, 0);
    pulse = List.filled(half * 2 + 1, 0);
    window = List.generate(half + 1, (i) => .5 + .5 * cos(pi * i / half));
    tempi = [for (double b = settings.minBpm; b <= settings.maxBpm; b += 2) b];
    if (tempi.isEmpty) throw ArgumentError('Tempo bounds must be ordered');
    cosines = [
      for (final b in tempi)
        List.generate(
          half + 1,
          (i) => window[i] * cos(2 * pi * b / 60 * period * i),
        ),
    ];
    sines = [
      for (final b in tempi)
        List.generate(
          half + 1,
          (i) => window[i] * sin(2 * pi * b / 60 * period * i),
        ),
    ];
  }
  BeatState add(double value, {bool includeContext = false}) {
    for (int i = half; i > 0; i--) {
      activation[i] = activation[i - 1];
    }
    activation[0] = value.isFinite ? max(0, value) : 0;
    for (int i = 0; i < pulse.length - 1; i++) {
      pulse[i] = pulse[i + 1];
    }
    pulse.last = 0;
    double best = 0, phase = 0, energy = 0;
    for (int j = 0; j <= half; j++) {
      energy += activation[j] * window[j];
    }
    for (int k = 0; k < tempi.length; k++) {
      double re = 0, im = 0;
      for (int j = 0; j <= half; j++) {
        re += activation[j] * cosines[k][j];
        im += activation[j] * sines[k][j];
      }
      final magnitude = re * re + im * im;
      if (magnitude > best) {
        best = magnitude;
        bpm = tempi[k];
        phase = atan2(im, re);
      }
    }
    if (energy > 1e-9) {
      // Full centered Hann window has sum = half. Future kernels are predictions.
      for (int j = -half; j <= half; j++) {
        pulse[j + half] +=
            window[j.abs()] *
            cos(2 * pi * bpm / 60 * period * j + phase) /
            half;
      }
    }
    final decision = (half + settings.lookahead / period).round().clamp(
      1,
      pulse.length - 2,
    );
    final stability = pulse[decision].clamp(0.0, 1.0);
    final now = count++ * period;
    final beat =
        energy > 1e-9 &&
        now >= min(settings.kernelSeconds / 2, 2) &&
        stability >= settings.threshold &&
        pulse[decision] > pulse[decision - 1] &&
        pulse[decision] >= pulse[decision + 1] &&
        now - lastBeat > 24 / max(1, bpm);
    if (beat) lastBeat = now;
    return BeatState(
      pulse[half],
      energy > 1e-9 ? bpm : 0,
      stability,
      beat,
      includeContext ? List<double>.of(pulse) : const [],
    );
  }
}

class BeatTrace {
  final List<double> times, pulse, bpm, stability, events;
  const BeatTrace(
    this.times,
    this.pulse,
    this.bpm,
    this.stability,
    this.events,
  );
  static const empty = BeatTrace([], [], [], [], []);
  Map<String, Object> toJson() => {
    'times': times,
    'pulse': pulse,
    'bpm': bpm,
    'stability': stability,
    'triggerTimes': events,
    'activation': 'spectral flux',
  };
}

BeatTrace trackBeats(
  List<double> times,
  List<double> activation,
  double period, [
  BeatSettings settings = const BeatSettings(),
]) {
  final tracker = CausalPlp(period, settings);
  final pulse = <double>[],
      bpm = <double>[],
      stability = <double>[],
      events = <double>[];
  for (int i = 0; i < times.length; i++) {
    final state = tracker.add(activation[i]);
    pulse.add(state.pulse);
    bpm.add(state.bpm);
    stability.add(state.stability);
    if (state.beat) events.add(times[i]);
  }
  return BeatTrace(times, pulse, bpm, stability, events);
}

/// Continuous PCM front end with trailing (causal) Hann frames. Buffers survive
/// UI refreshes; each received sample is processed once.
class BeatAudioStream {
  final int sampleRate;
  final BeatSettings settings;
  late final CausalPlp _plp;
  final _samples = <double>[];
  final _times = <double>[],
      _pulse = <double>[],
      _bpm = <double>[],
      _stability = <double>[],
      _events = <double>[];
  List<double>? _previous;
  int _consumed = 0;
  static const windowSize = 2048, hopSize = 512;
  BeatAudioStream(this.sampleRate, this.settings) {
    _plp = CausalPlp(hopSize / sampleRate, settings);
  }
  BeatTrace add(List<double> samples) {
    _samples.addAll(samples);
    int start = 0;
    while (start + windowSize <= _samples.length) {
      final spectrum = _beatFft.realFft(
        List.generate(windowSize, (i) => _samples[start + i] * _beatWindow[i]),
      );
      final magnitudes = List.generate(
        windowSize ~/ 2 + 1,
        (i) =>
            sqrt(spectrum[i].x * spectrum[i].x + spectrum[i].y * spectrum[i].y),
      );
      final total = magnitudes.fold(0.0, (a, b) => a + b);
      final normalized =
          magnitudes.map((x) => total > 1e-9 ? x / total : 0.0).toList();
      double flux = 0;
      if (_previous != null && total > 1e-9) {
        for (int i = 0; i < normalized.length; i++) {
          final delta = max(0, normalized[i] - _previous![i]);
          flux += delta * delta;
        }
      }
      _previous = normalized;
      final state = _plp.add(sqrt(flux));
      final time = (_consumed + start + windowSize) / sampleRate;
      _times.add(time);
      _pulse.add(state.pulse);
      _bpm.add(state.bpm);
      _stability.add(state.stability);
      if (state.beat) _events.add(time);
      start += hopSize;
    }
    _samples.removeRange(0, start);
    _consumed += start;
    final limit = max(1, (8 * sampleRate / hopSize).round());
    if (_times.length > limit) {
      final remove = _times.length - limit;
      for (final list in [_times, _pulse, _bpm, _stability]) {
        list.removeRange(0, remove);
      }
    }
    if (_times.isNotEmpty) _events.removeWhere((x) => x < _times.first);
    return BeatTrace(
      List.of(_times),
      List.of(_pulse),
      List.of(_bpm),
      List.of(_stability),
      List.of(_events),
    );
  }
}
