import 'dart:async';
import 'dart:isolate';
import 'dart:io';
import 'package:wav/wav.dart';
import 'analysis.dart';
import 'native_cqt.dart';
import '../music/beat_tracker.dart';

/// Serial queue: mic capture drops superseded work instead of queuing frames.
class AnalysisWorker {
  Isolate? _isolate;
  SendPort? _port;
  Future<void>? _starting;
  final _responses = ReceivePort();
  final _pending = <int, Completer<Object>>{};
  int _serial = 0;
  bool _closed = false;
  Future<void> _start() async {
    final ready = Completer<void>();
    _responses.listen((message) {
      if (message is SendPort) {
        _port = message;
        ready.complete();
        return;
      }
      final response = message as List;
      final pending = _pending.remove(response[0]);
      if (response[1] is! String) {
        pending?.complete(response[1]);
      } else {
        pending?.completeError(StateError(response[1] as String));
      }
    });
    _isolate = await Isolate.spawn(_entry, _responses.sendPort);
    if (_closed) {
      _isolate?.kill();
      return;
    }
    await ready.future;
  }

  Future<Object> _request(Map<String, dynamic> request) async {
    if (_closed) throw StateError('Analysis worker disposed');
    await (_starting ??= _start());
    if (_closed) throw StateError('Analysis worker disposed');
    final id = ++_serial;
    final done = Completer<Object>();
    _pending[id] = done;
    _port!.send([id, request]);
    return done.future;
  }

  Future<AnalysisResult> analyze(Map<String, dynamic> request) async =>
      await _request(request) as AnalysisResult;
  Future<List<double>> pitch(double time) async =>
      await _request({'pitchAt': time}) as List<double>;
  Future<BeatTrace> beats(
    BeatSettings settings, [
    AnalysisResult? data,
  ]) async =>
      await _request({'beatSettings': settings, 'beatData': data}) as BeatTrace;
  Future<BeatTrace> beatChunk(
    List<double> samples,
    int rate,
    BeatSettings settings, {
    bool reset = false,
  }) async =>
      await _request({
            'beatChunk': samples,
            'beatRate': rate,
            'beatSettingsLive': settings,
            'beatReset': reset,
          })
          as BeatTrace;
  static void _entry(SendPort output) {
    final input = ReceivePort();
    output.send(input.sendPort);
    AnalysisResult? file;
    NativeCqt? pitch;
    BeatAudioStream? liveBeat;
    input.listen((message) {
      final request = message as List;
      try {
        final options = request[1] as Map<String, dynamic>;
        if (options.containsKey('beatChunk')) {
          final rate = options['beatRate'] as int;
          if (liveBeat == null ||
              options['beatReset'] == true ||
              liveBeat!.sampleRate != rate) {
            liveBeat = BeatAudioStream(
              rate,
              options['beatSettingsLive'] as BeatSettings,
            );
          }
          output.send([
            request[0],
            liveBeat!.add(options['beatChunk'] as List<double>),
          ]);
        } else if (options.containsKey('beatSettings')) {
          final data = options['beatData'] as AnalysisResult? ?? file;
          if (data == null) throw StateError('No recording loaded');
          output.send([
            request[0],
            beatAnalysis(data, options['beatSettings'] as BeatSettings),
          ]);
        } else if (options.containsKey('pitchAt')) {
          if (file == null) throw StateError('No file loaded');
          final bins = (pitch ??= NativeCqt()).transform(
            file!.samples,
            ((options['pitchAt'] as double) * file!.sampleRate).round(),
          );
          output.send([request[0], bins]);
        } else {
          if (options['wavPath'] != null) {
            final wav = Wav.read(
              File(options['wavPath'] as String).readAsBytesSync(),
            );
            final samples = wav.toMono();
            if (samples.length / wav.samplesPerSecond > 480) {
              throw StateError('Choose a recording up to eight minutes');
            }
            options['samples'] = samples;
            options['sampleRate'] = wav.samplesPerSecond;
          }
          final result = analyzeAudio(options);
          if (options['source'] == 'file') file = result;
          output.send([request[0], result]);
        }
      } catch (e) {
        output.send([request[0], e.toString()]);
      }
    });
  }

  void dispose() {
    _closed = true;
    _isolate?.kill(priority: Isolate.immediate);
    _responses.close();
    for (final pending in _pending.values) {
      pending.completeError(StateError('Analysis worker disposed'));
    }
    _pending.clear();
  }
}
