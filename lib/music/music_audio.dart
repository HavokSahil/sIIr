import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import '../services/audio_decoder.dart';
import '../services/mic_controller.dart';
import '../workbench/analysis.dart';
import '../workbench/analysis_worker.dart';

/// Shared local audio input for the visualizer. No audio is uploaded.
class MusicAudio extends ChangeNotifier {
  final player = AudioPlayer();
  final mic = MicController(sampleRate: 22050);
  final worker = AnalysisWorker();
  final _subscriptions = <StreamSubscription>[];
  AnalysisResult? data;
  String? path;
  String name = 'Choose music or microphone', error = '';
  bool live = false, playing = false, busy = false, _closed = false;
  double position = 0, energy = 0, bass = 0, treble = 0, onset = 0;
  double _low = 0, _lastEnergy = 0;
  int _generation = 0;
  bool _scrubbing = false;
  MusicAudio() {
    player.positionUpdater = TimerPositionUpdater(
      getPosition: player.getCurrentPosition,
      interval: const Duration(milliseconds: 33),
    );
    _subscriptions.add(
      player.onPositionChanged.listen((p) {
        if (busy || _scrubbing || live) return;
        position = p.inMilliseconds / 1000;
        final d = data;
        if (d != null && d.frames.isNotEmpty) {
          final f = d.frames[d.nearest(position)];
          energy = (f.values[0] * 4).clamp(0.0, 1.0);
          final lowEnd = max(1, (250 * d.window / d.sampleRate).round());
          double lo = 0, hi = 0, total = 0;
          for (int i = 0; i < f.spectrum.length; i++) {
            final e = f.spectrum[i] * f.spectrum[i];
            total += e;
            if (i < lowEnd) lo += e;
            if (i > 2000 * d.window / d.sampleRate) hi += e;
          }
          bass = total > 1e-12 ? sqrt(lo / total) * energy : 0;
          treble = total > 1e-12 ? sqrt(hi / total) * energy : 0;
          onset = (f.values[6] * 8).clamp(0.0, 1.0);
        }
        _notify();
      }),
    );
    _subscriptions.add(
      player.onPlayerStateChanged.listen((state) {
        playing = state == PlayerState.playing;
        if (!playing && !live) energy = bass = treble = onset = 0;
        _notify();
      }),
    );
    _subscriptions.add(
      mic.audioDataStream.listen(
        (samples) {
          if (!live || samples.isEmpty) return;
          double sum = 0, lowSum = 0, highSum = 0;
          for (final x in samples) {
            _low += .065 * (x - _low);
            sum += x * x;
            lowSum += _low * _low;
            highSum += (x - _low) * (x - _low);
          }
          energy = (sqrt(sum / samples.length) * 5).clamp(0.0, 1.0);
          bass = (sqrt(lowSum / samples.length) * 5).clamp(0.0, 1.0);
          treble = (sqrt(highSum / samples.length) * 5).clamp(0.0, 1.0);
          onset = max(0, energy - _lastEnergy) * 3;
          _lastEnergy = energy;
          _notify();
        },
        onError: (Object e) {
          error = '$e';
          live = false;
          _notify();
        },
      ),
    );
  }
  void _notify() {
    if (!_closed) notifyListeners();
  }

  Future<void> microphone() async {
    final generation = ++_generation;
    error = '';
    try {
      await player.pause();
      if (_closed) return;
      if (live) {
        await mic.stop();
        live = false;
      } else {
        await mic.setSampleRate(22050);
        await mic.listening();
        if (_closed || generation != _generation) return;
        live = mic.isListening();
        if (!live) error = 'Microphone permission is required.';
      }
      energy = bass = treble = onset = 0;
      _notify();
    } catch (e) {
      error = '$e';
      _notify();
    }
  }

  Future<void> import() async {
    if (busy) return;
    final picked = await FilePicker.platform.pickFiles(type: FileType.audio);
    if (_closed || picked == null || picked.files.single.path == null) return;
    final generation = ++_generation;
    busy = true;
    error = '';
    _notify();
    try {
      await mic.stop();
      live = false;
      await player.release();
      if (picked.files.single.size > 100 * 1024 * 1024) {
        throw StateError('Choose a file under 100 MB');
      }
      final original = picked.files.single.path!;
      final wav =
          original.toLowerCase().endsWith('.wav')
              ? original
              : await AudioDecoder.convertToWav(original);
      final result = await worker.analyze({
        'wavPath': wav,
        'source': 'file',
        'sampleRate': 22050,
        'window': 2048,
        'hop': 1024,
        'lightweight': true,
      });
      if (_closed || generation != _generation) return;
      data = result;
      path = wav;
      name = picked.files.single.name;
      position = 0;
    } catch (e) {
      error = 'Could not open audio: $e';
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> toggle() async {
    if (path == null || busy) return;
    try {
      await mic.stop();
      live = false;
      if (playing) {
        await player.pause();
      } else {
        if (data != null && position >= data!.duration) position = 0;
        await player.play(
          DeviceFileSource(path!),
          position: Duration(milliseconds: (position * 1000).round()),
        );
      }
    } catch (e) {
      error = 'Playback failed: $e';
      _notify();
    }
  }

  void previewSeek(double value) {
    _scrubbing = true;
    position = value;
    _notify();
  }

  Future<void> seek(double value) async {
    _scrubbing = true;
    position = value;
    _notify();
    try {
      if (path != null && player.source != null) {
        await player.seek(Duration(milliseconds: (value * 1000).round()));
      }
    } catch (e) {
      error = 'Seek failed: $e';
      _notify();
    } finally {
      _scrubbing = false;
    }
  }

  @override
  void dispose() {
    _closed = true;
    _generation++;
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    mic.dispose();
    player.dispose();
    worker.dispose();
    super.dispose();
  }
}
