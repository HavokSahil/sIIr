import 'dart:async';
import 'package:audio_streamer/audio_streamer.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shirr/core/constants.dart';

class MicController {
  final int sampleRate;
  final int numChannels;
  final requiredPermission = Permission.microphone;

  final AudioStreamer _audioStreamer = AudioStreamer();
  StreamSubscription<List<double>>? _streamSubscription;
  final StreamController<List<double>> _streamController =
      StreamController.broadcast();

  bool _isListening = false;

  MicController({
    this.sampleRate = Constants.defaultSampleRate,
    this.numChannels = Constants.defaultNumChannels,
  });

  Future<bool> _isActionPermitted() async {
    var permission = await requiredPermission.status;
    if (!permission.isGranted) {
      if (await requiredPermission.shouldShowRequestRationale) {
        // Optional: show rationale dialog
      }
      permission = await requiredPermission.request();
    }
    return permission.isGranted;
  }

  Future<void> listening() async {
    if (!_isListening) {
      bool allowed = await _isActionPermitted();
      if (!allowed) return;

      _streamSubscription = _audioStreamer.audioStream.listen((
        List<double> buffer,
      ) {
        _streamController.add(buffer); // Forward audio data to streamController
      });

      _isListening = true;
    }
  }

  Future<void> stop() async {
    if (_isListening) {
      await _streamSubscription?.cancel();
      _isListening = false;
    }
  }

  Stream<List<double>> get audioDataStream => _streamController.stream;

  Future<int> getSampleRate() async => _audioStreamer.actualSampleRate;

  Future<void> setSampleRate(int sampleRate) async {
    // The native recorder exists only after the stream starts. Its actual
    // sample rate is read when the first audio buffer arrives.
    _audioStreamer.sampleRate = sampleRate;
  }

  bool isListening() => _isListening;

  void dispose() {
    _streamSubscription?.cancel();
    _streamController.close();
  }
}
