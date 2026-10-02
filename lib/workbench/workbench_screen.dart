import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../services/audio_decoder.dart';
import '../services/mic_controller.dart';
import 'analysis.dart';
import '../music/beat_tracker.dart';
import 'analysis_worker.dart';
import 'plot.dart';
import 'tools.dart';
import 'shirr_chrome.dart';
import '../core/constants.dart';
import '../screens/audio_analyzer/theme_colors.dart';

enum AnalysisSource { microphone, file }

class WorkbenchScreen extends StatefulWidget {
  final AnalysisResult? initialData;
  final bool loadDemo;
  final String initialToolId;
  const WorkbenchScreen({
    super.key,
    this.initialData,
    this.loadDemo = true,
    this.initialToolId = 'waveform',
  });
  @override
  State<WorkbenchScreen> createState() => _WorkbenchScreenState();
}

class _WorkbenchScreenState extends State<WorkbenchScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _discMotion;
  final _worker = AnalysisWorker();
  BeatSettings _beatSettings = const BeatSettings();
  bool _beatBusy = false;
  final _beatSamples = <double>[];
  BeatSettings? _liveBeatSettings;
  AnalysisResult? _beatData;
  final _clock = ValueNotifier<int>(0);
  final _changes = ValueNotifier<int>(0);
  Timer? _playbackTimer;
  final _positionClock = Stopwatch();
  double _positionBase = 0;
  bool _fullscreen = false,
      _follow = true,
      _pitchBusy = false,
      _scrubbing = false;
  double _pitchTime = -1;
  List<double> _pitchBins = const [];
  int? _micRate;
  final _player = AudioPlayer();
  final _mic = MicController();
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  final List<Map<String, dynamic>> _pins = [], _annotations = [];
  final _live = <double>[];
  AnalysisResult? _data;
  AnalysisTool _tool = tools.first;
  String _source = 'No recording', _mode = 'Pan';
  String? _path;
  AnalysisSource _sourceMode = AnalysisSource.file;
  AnalysisResult? _fileData;
  String? _filePath;
  String _fileName = 'No audio file loaded';
  double _fileCursor = 0, _fileRangeStart = 0, _fileRangeEnd = 18;
  final List<Map<String, dynamic>> _filePins = [], _fileAnnotations = [];
  bool _switchingSource = false;
  bool _busy = false,
      _playing = false,
      _listening = false,
      _showInspector = false;
  double _cursor = 0,
      _viewStart = 0,
      _viewEnd = 18,
      _rangeStart = 0,
      _rangeEnd = 18,
      _gain = 1.5;
  double _frequencyStart = 0, _frequencyEnd = 11025, _frequencyCursor = 440;
  double? _pcaMinX, _pcaMaxX, _pcaMinY, _pcaMaxY;
  int _window = 1024, _hop = 512, _generation = 0;
  DateTime _lastLive = DateTime.fromMillisecondsSinceEpoch(0);
  Map<String, dynamic>? _experiment;

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    // Modal routes have their own element tree: edits must refresh open sheets.
    _changes.value++;
  }

  @override
  void initState() {
    super.initState();
    _discMotion = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    );
    _subscriptions.add(
      _player.onPositionChanged.listen((position) {
        if (mounted && _playing) {
          _positionBase = position.inMilliseconds / 1000;
          _positionClock
            ..reset()
            ..start();
        }
      }),
    );
    _subscriptions.add(
      _player.onPlayerStateChanged.listen((state) {
        if (mounted) {
          setState(() => _playing = state == PlayerState.playing);
          _updateDiscMotion();
        }
      }),
    );
    _subscriptions.add(
      _player.onPlayerComplete.listen((_) {
        if (mounted) setState(() => _cursor = 0);
      }),
    );
    _subscriptions.add(_mic.audioDataStream.listen(_receiveMic));
    _playbackTimer = Timer.periodic(const Duration(milliseconds: 33), (_) {
      if (!mounted || !_playing || _scrubbing || _data == null) return;
      _cursor = min(
        _data!.duration,
        _positionBase + _positionClock.elapsedMilliseconds / 1000,
      );
      _clock.value++;
    });
    _tool = tools.firstWhere((tool) => tool.id == widget.initialToolId);
    _data = widget.initialData;
    if (_data != null) {
      _rangeEnd = _data!.duration;
      _viewEnd = min(1, _data!.duration);
      _source = 'Test recording';
      _fileData = _data;
      _fileName = _source;
      _fileRangeEnd = _data!.duration;
    }
    if (widget.loadDemo) _demo();
  }

  @override
  void dispose() {
    _generation++;
    if (_fullscreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    _playbackTimer?.cancel();
    _clock.dispose();
    _changes.dispose();
    _worker.dispose();
    _discMotion.dispose();
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _mic.dispose();
    _player.dispose();
    super.dispose();
  }

  void _message(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _analyze(
    List<double> samples,
    int rate, {
    bool reset = true,
    bool rememberFile = true,
    String? wavPath,
  }) async {
    final generation = ++_generation;
    if (rememberFile) {
      setState(() => _busy = true);
    } else {
      _busy = true;
    }
    try {
      final result = await _worker.analyze({
        'samples': samples,
        if (wavPath != null) 'wavPath': wavPath,
        'sampleRate': rate,
        'window': _window,
        'hop': rememberFile ? _hop : max(_hop, 2048),
        'lightweight':
            !rememberFile &&
            (_tool.id == 'beats' ||
                !['Statistics', 'Structure'].contains(_tool.section) &&
                    _tool.id != 'tempo'),
        'cqt': Platform.isAndroid && !rememberFile && _tool.id == 'cqt',

        'source': rememberFile ? 'file' : 'microphone',
      });
      if (!mounted || generation != _generation) return;
      setState(() {
        _data = result;
        if (rememberFile && _sourceMode == AnalysisSource.file) {
          _pitchBins = const [];
          _pitchTime = -1;
          _fileData = result;
          _filePath = _path;
          _fileName = _source;
        }
        _busy = false;
        if (reset) {
          _cursor = 0;
          _viewStart = 0;
          _viewEnd = max(0.01, min(1, result.duration));
          _rangeStart = 0;
          _rangeEnd = result.duration;
          _frequencyStart = 0;
          _frequencyEnd = result.sampleRate / 2;
          _experiment = null;
          _pcaMinX = _pcaMaxX = _pcaMinY = _pcaMaxY = null;
        }
      });
    } catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() => _busy = false);
      _message('Analysis failed: $e');
    }
  }

  Future<void> _demo() async {
    await _mic.stop();
    await _player.stop();
    if (!mounted) return;
    setState(() {
      _listening = false;
      _sourceMode = AnalysisSource.file;
      _filePins.clear();
      _fileAnnotations.clear();
      _source = 'Demo · three harmonic sections · 120 BPM pulse';
      _pins.clear();
      _annotations.clear();
    });
    try {
      final samples = demoSamples();
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/siir_observatory_demo.wav');
      await file.writeAsBytes(encodeWav(samples, 22050));
      _path = file.path;
      await _player.setSource(DeviceFileSource(_path!));
      if (mounted) await _analyze(samples, 22050);
    } catch (e) {
      _message('Could not load demo: $e');
    }
  }

  Future<void> _import() async {
    try {
      final picked = await FilePicker.platform.pickFiles(type: FileType.audio);
      if (picked == null || !mounted) return;
      final selected = picked.files.single;
      if (selected.path == null) {
        _message('This file has no accessible local path.');
        return;
      }
      if (selected.size > 100 * 1024 * 1024) {
        _message('Choose audio smaller than 100 MB.');
        return;
      }
      await _mic.stop();
      await _player.stop();
      if (!mounted) return;
      setState(() {
        _busy = true;
        _listening = false;
        _sourceMode = AnalysisSource.file;
      });
      final original = selected.path!;
      final path =
          original.toLowerCase().endsWith('.wav')
              ? original
              : await AudioDecoder.convertToWav(original);
      _path = original;
      await _player.setSource(DeviceFileSource(original));
      if (!mounted) return;
      setState(() {
        _source = selected.name;
        _filePins.clear();
        _fileAnnotations.clear();
        _pins.clear();
        _annotations.clear();
      });
      await _analyze(const [], 22050, wavPath: path);
    } catch (e) {
      if (mounted) setState(() => _busy = false);
      _message('Import failed. Try a PCM WAV file. $e');
    }
  }

  void _rememberFileSession() {
    if (_sourceMode != AnalysisSource.file) return;
    _fileData = _data;
    _filePath = _path;
    _fileName = _source;
    _fileCursor = _cursor;
    _fileRangeStart = _rangeStart;
    _fileRangeEnd = _rangeEnd;
    _filePins
      ..clear()
      ..addAll(_pins.map((p) => Map<String, dynamic>.from(p)));
    _fileAnnotations
      ..clear()
      ..addAll(_annotations.map((p) => Map<String, dynamic>.from(p)));
  }

  Future<void> _selectSource(AnalysisSource source) async {
    if (_switchingSource || _sourceMode == source) return;
    setState(() => _switchingSource = true);
    try {
      if (source == AnalysisSource.microphone) {
        await _toggleMic();
      } else {
        ++_generation; // Discard any pending microphone analysis.
        await _mic.stop();
        if (!mounted) return;
        setState(() {
          _sourceMode = AnalysisSource.file;
          _listening = false;
          _busy = false;
          _data = _fileData;
          _path = _filePath;
          _source = _fileName;
          _cursor = _fileCursor;
          _rangeStart = _fileRangeStart;
          _rangeEnd =
              _fileData == null ? 0 : min(_fileRangeEnd, _fileData!.duration);
          _viewStart = 0;
          _viewEnd = max(.01, min(1, _fileData?.duration ?? 1));
          _pins
            ..clear()
            ..addAll(_filePins.map((p) => Map<String, dynamic>.from(p)));
          _annotations
            ..clear()
            ..addAll(_fileAnnotations.map((p) => Map<String, dynamic>.from(p)));
          _experiment = null;
        });
        _updateDiscMotion();
        if (_path != null) await _player.setSource(DeviceFileSource(_path!));
        if (_fileData == null && mounted) await _import();
      }
    } catch (e) {
      _message('Could not switch audio source: $e');
    } finally {
      if (mounted) setState(() => _switchingSource = false);
    }
  }

  Future<void> _toggleMic() async {
    if (_listening) {
      await _mic.stop();
      if (mounted) setState(() => _listening = false);
      _updateDiscMotion();
      return;
    }
    try {
      await _player.stop();
      await _mic.setSampleRate(22050);
      await _mic.listening();
      if (!mounted) return;
      if (!_mic.isListening()) {
        _message('Microphone permission is required to capture audio.');
        return;
      }
      _rememberFileSession();
      ++_generation;
      setState(() {
        _sourceMode = AnalysisSource.microphone;
        _listening = true;
        _playing = false;
        _busy = false;
        _source = 'Microphone · live analysis';
        _live.clear();
        _beatSamples.clear();
        _liveBeatSettings = null;
        _data = null;
        _path = null;
        _cursor = _rangeStart = _viewStart = 0;
        _rangeEnd = _viewEnd = 4;
        _micRate = null;
        _pins.clear();
        _annotations.clear();
        _experiment = null;
      });
      _updateDiscMotion();
    } catch (e) {
      _message('Could not start microphone: $e');
    }
  }

  void _receiveMic(List<double> chunk) async {
    if (!_listening || !mounted) return;
    final rate = _micRate ??= await _mic.getSampleRate();
    if (!mounted || !_listening) return;
    _live.addAll(chunk);
    if (_tool.id == 'beats') {
      _beatSamples.addAll(chunk);
    } else {
      _beatSamples.clear();
      _liveBeatSettings = null;
    }
    if (_live.length > rate * 4) {
      _live.removeRange(0, _live.length - rate * 4);
    }
    if (_busy || DateTime.now().difference(_lastLive).inMilliseconds < 180) {
      return;
    }
    _lastLive = DateTime.now();
    await _analyze(
      List<double>.from(
        _tool.id == 'waveform'
            ? _live.skip(max(0, _live.length - rate))
            : _live,
      ),
      rate,
      rememberFile: false,
      reset: false,
    );
    if (_tool.id == 'beats' && mounted && _listening && _data != null) {
      final pending = List<double>.of(_beatSamples);
      _beatSamples.clear();
      final resetBeat = !identical(_liveBeatSettings, _beatSettings);
      _liveBeatSettings = _beatSettings;
      try {
        final trace = await _worker.beatChunk(
          pending,
          rate,
          _beatSettings,
          reset: resetBeat,
        );
        if (mounted && _listening && _data != null && trace.times.isNotEmpty) {
          final shift = trace.times.last - _data!.duration;
          _data!.beats = BeatTrace(
            trace.times.map((x) => x - shift).toList(),
            trace.pulse,
            trace.bpm,
            trace.stability,
            trace.events.map((x) => x - shift).toList(),
          );
        }
      } catch (e) {
        if (mounted) _message('Live beat tracking failed: $e');
      }
    }
    if (mounted && _listening) {
      setState(() {
        _cursor = _data?.duration ?? 0;
        _viewStart = 0;
        _viewEnd = max(.01, _cursor);
      });
    }
  }

  Future<void> _play() async {
    if (_sourceMode == AnalysisSource.microphone) {
      await _toggleMic();
      return;
    }
    if (_path == null || _busy) return;
    try {
      if (_playing) {
        await _player.pause();
      } else {
        _positionBase = _cursor;
        _positionClock
          ..reset()
          ..start();
        await _player.play(
          DeviceFileSource(_path!),
          position: Duration(milliseconds: (_cursor * 1000).round()),
        );
      }
    } catch (e) {
      _message('Could not play audio: $e');
    }
  }

  void _inspect(double time) {
    final data = _data;
    if (data == null) return;
    setState(() {
      _scrubbing = false;
      _cursor = time.clamp(0.0, data.duration);
      _positionBase = _cursor;
      _positionClock
        ..reset()
        ..start();
    });
    if (_mode == 'Pin') {
      _editMarker(false, time: _cursor);
    } else if (_path != null && _playing) {
      _player
          .seek(Duration(milliseconds: (_cursor * 1000).round()))
          .catchError((Object e) => _message('Could not seek audio: $e'));
    }
  }

  Future<void> _editMarker(
    bool annotation, {
    double? time,
    double? frequency,
    int? index,
  }) async {
    final list = annotation ? _annotations : _pins;
    final existing = index == null ? null : list[index];
    final controller = TextEditingController(
      text: existing?['label'] as String? ?? '',
    );
    final location = time ?? existing?['time'] as double? ?? _cursor;
    final label = await showDialog<String>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(annotation ? 'Annotate section' : 'Label pin'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${location.toStringAsFixed(3)} s${frequency != null ? ' / ${frequency.toStringAsFixed(1)} Hz' : ''}',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  autofocus: true,
                  maxLength: 80,
                  decoration: const InputDecoration(labelText: 'Label'),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, controller.text.trim()),
                child: const Text('Save'),
              ),
            ],
          ),
    );
    controller.dispose();
    if (!mounted || label == null || label.isEmpty) return;
    setState(() {
      final marker = <String, dynamic>{
        'time': location,
        'label': label,
        if (frequency != null || existing?['frequency'] != null)
          'frequency': frequency ?? existing!['frequency'],
      };
      if (index == null) {
        list.add(marker);
      } else {
        list[index] = marker;
      }
    });
  }

  Future<void> _export() async {
    final data = _data;
    if (data == null) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File(
        '${dir.path}/siir_${DateTime.now().millisecondsSinceEpoch}.json',
      );
      final payload =
          data.toJson()..addAll({
            'source': _source,
            'sourceMode': _sourceMode.name,
            'statisticsMode':
                _sourceMode == AnalysisSource.microphone
                    ? 'liveRollingBuffer'
                    : 'fileFrames',
            'selectedTime': _cursor,
            if (_tool.id == 'cqt')
              'ecqt': {
                'cursorTime': _pitchTime,
                'minimumFrequency': 65.406391,
                'binsPerOctave': 12,
                'magnitudes': _pitchBins,
              },
            'interval': [_rangeStart, _rangeEnd],
            'viewport': [_viewStart, _viewEnd],
            'frequencyViewport': [_frequencyStart, _frequencyEnd],
            'pcaViewport': [_pcaMinX, _pcaMaxX, _pcaMinY, _pcaMaxY],
            'pins': _pins,
            'annotations': _annotations,
            'experiment': _experiment,
            'validity':
                'Exploratory measurements. 48-tap windowed-sinc resampling with finite transition band. Tempo and boundaries are candidates.',
          });
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(payload),
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder:
            (context) => AlertDialog(
              title: const Text('Analysis exported'),
              content: SelectableText(
                'Saved locally:\n${file.path}\n\nIncludes measurements, settings, pins, intervals, annotations and experiment results.',
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: file.path));
                  },
                  child: const Text('Copy path'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Done'),
                ),
              ],
            ),
      );
    } catch (e) {
      _message('Export failed: $e');
    }
  }

  Future<void> _runGain() async {
    final data = _data;
    if (data == null) return;
    final lo = (_rangeStart * data.sampleRate).floor().clamp(
      0,
      data.samples.length,
    );
    final hi = (_rangeEnd * data.sampleRate).ceil().clamp(
      lo,
      data.samples.length,
    );
    if (hi - lo < data.window) {
      _message('Select at least one complete frame.');
      return;
    }
    setState(() => _busy = true);
    final interval = data.samples.sublist(lo, hi);
    final gain = _gain;
    try {
      final request = {
        'samples': interval,
        'sampleRate': data.sampleRate,
        'window': data.window,
        'hop': data.hop,
      };
      final before = await compute(analyzeAudio, request);
      final after = await compute(analyzeAudio, {
        ...request,
        'samples': interval.map((x) => x * gain).toList(),
      });
      if (!mounted) return;
      double average(AnalysisResult d, int i) =>
          d.frames.fold(0.0, (s, f) => s + f.values[i]) /
          max(1, d.frames.length);
      final rms = average(before, 0), measured = average(after, 0);
      setState(() {
        _busy = false;
        _experiment = {
          'gain': gain,
          'interval': [_rangeStart, _rangeEnd],
          'beforeRms': rms,
          'predictedRms': rms * gain,
          'measuredRms': measured,
          'rmsResidual': measured - rms * gain,
          'centroidDeltaHz': average(after, 1) - average(before, 1),
          'flatnessDelta': average(after, 4) - average(before, 4),
          'deltaDb': 20 * log(gain) / ln10,
          'wouldClip': interval.any((x) => (x * gain).abs() > 1),
        };
      });
    } catch (e) {
      if (mounted) setState(() => _busy = false);
      _message('Experiment failed: $e');
    }
  }

  void _maths() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor:
          Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFF111111)
              : const Color(0xFFFAFAFA),
      builder:
          (context) => DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.78,
            maxChildSize: 0.95,
            builder:
                (context, scroll) => ListView(
                  controller: scroll,
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
                  children: [
                    Text(
                      '${_tool.section.toUpperCase()} / MATHEMATICAL NOTE',
                      style: _mono,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _tool.title,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      _tool.intuition,
                      style: const TextStyle(fontSize: 17, height: 1.6),
                    ),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24),
                        color: ThemeColors.of(
                          context,
                        ).textColor.withValues(alpha: 0.05),
                        border: Border.all(
                          color: ThemeColors.of(
                            context,
                          ).textColor.withValues(alpha: 0.2),
                        ),
                      ),
                      child: SelectableText(
                        _tool.formula,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 16,
                          height: 1.9,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text('ASSUMPTIONS & VALIDITY', style: _mono),
                    const SizedBox(height: 12),
                    Text(_tool.rigor, style: const TextStyle(height: 1.7)),
                    const SizedBox(height: 24),
                    Text('NOTATION', style: _mono),
                    const SizedBox(height: 12),
                    const Text(
                      'x: mono PCM · fₛ: sample rate · N: frame length · H: hop · m: frame index · k: frequency bin · A: magnitude · P: power · M: frame count · ε: numerical floor.\n\nMeasurements are exploratory. Imported audio is resampled with a 48-tap Hann-windowed sinc low-pass filter (256 phases). Its finite transition band attenuates, but does not ideally eliminate, aliasing. Native 22,050 Hz PCM bypasses resampling.',
                      style: TextStyle(height: 1.7),
                    ),
                  ],
                ),
          ),
    );
  }

  TextStyle get _mono => TextStyle(
    fontFamily: 'monospace',
    fontSize: 11,
    letterSpacing: 1.2,
    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
  );
  Widget _tag(String text, {Color? color}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: (color ?? ThemeColors.of(context).textColor).withValues(
        alpha: 0.05,
      ),
      border: Border.all(
        color: (color ?? ThemeColors.of(context).textColor).withValues(
          alpha: 0.2,
        ),
      ),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontFamily: 'monospace',
        fontSize: 10,
        color: color ?? ThemeColors.of(context).textColor,
      ),
    ),
  );

  Future<void> _requestBeats() async {
    final data = _data;
    if (data == null || _beatBusy) return;
    _beatBusy = true;
    _beatData = data;
    final settings = _beatSettings;
    try {
      final trace = await _worker.beats(
        settings,
        widget.initialData != null || _sourceMode == AnalysisSource.microphone
            ? data
            : null,
      );
      if (mounted && identical(data, _data)) setState(() => data.beats = trace);
    } catch (e) {
      if (mounted) _message('Beat tracking failed: $e');
    } finally {
      _beatBusy = false;
      if (mounted && !identical(settings, _beatSettings)) {
        _beatData = null;
        _requestBeats();
      }
    }
  }

  Widget _beatStatus() {
    final trace = _data!.beats;
    int index = 0;
    while (index + 1 < trace.times.length &&
        trace.times[index + 1] <= _cursor) {
      index++;
    }
    final bpm = trace.bpm.isEmpty ? 0.0 : trace.bpm[index];
    final confidence = trace.stability.isEmpty ? 0.0 : trace.stability[index];
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        '${bpm > 0 ? bpm.toStringAsFixed(0) : '—'} BPM · stability ${confidence.toStringAsFixed(2)} · ${trace.events.where((t) => t <= _cursor).length} beats',
        style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
      ),
    );
  }

  Widget _beatControls() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('PLP CONTROLS', style: TextStyle(fontFamily: 'monospace')),
      for (final entry in [
        ('Minimum BPM', _beatSettings.minBpm, 30.0, 120.0),
        ('Maximum BPM', _beatSettings.maxBpm, 122.0, 240.0),
        ('Context (seconds)', _beatSettings.kernelSeconds, 2.0, 8.0),
        ('Lookahead (seconds)', _beatSettings.lookahead, 0.0, .3),
        ('Stability threshold', _beatSettings.threshold, 0.0, .5),
      ]) ...[
        Text('${entry.$1}: ${entry.$2.toStringAsFixed(2)}'),
        Slider(
          value: entry.$2,
          min: entry.$3,
          max: entry.$4,
          onChanged:
              (v) => setState(() {
                _beatSettings = BeatSettings(
                  minBpm: entry.$1 == 'Minimum BPM' ? v : _beatSettings.minBpm,
                  maxBpm: entry.$1 == 'Maximum BPM' ? v : _beatSettings.maxBpm,
                  kernelSeconds:
                      entry.$1 == 'Context (seconds)'
                          ? v
                          : _beatSettings.kernelSeconds,
                  lookahead:
                      entry.$1 == 'Lookahead (seconds)'
                          ? v
                          : _beatSettings.lookahead,
                  threshold:
                      entry.$1 == 'Stability threshold'
                          ? v
                          : _beatSettings.threshold,
                );
              }),
          onChangeEnd: (_) {
            _beatData = null;
            if (!_listening) _requestBeats();
          },
        ),
      ],
      const Text(
        'Flux activation · causal window · predicted lookahead. Early estimates need a few seconds of rhythm.',
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, size) {
        final wide = size.maxWidth >= 1080, desktop = size.maxWidth >= 760;
        return CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.equal): () {
              if (_data != null) _zoom(0.7);
            },
            const SingleActivator(LogicalKeyboardKey.minus): () {
              if (_data != null) _zoom(1.4);
            },
            const SingleActivator(LogicalKeyboardKey.keyP):
                () => _editMarker(
                  false,
                  frequency: _tool.id == 'spectrum' ? _frequencyCursor : null,
                ),
            const SingleActivator(LogicalKeyboardKey.keyI):
                () => setState(() => _mode = 'Pan'),
            const SingleActivator(LogicalKeyboardKey.keyR):
                () => setState(() {
                  _viewStart = 0;
                  _viewEnd = _data?.duration ?? 18;
                }),
            const SingleActivator(LogicalKeyboardKey.space): () {
              if (!_busy) _play();
            },
            const SingleActivator(LogicalKeyboardKey.arrowRight): () {
              if (_data != null) _inspect(_cursor + 0.1);
            },
            const SingleActivator(LogicalKeyboardKey.arrowLeft): () {
              if (_data != null) _inspect(_cursor - 0.1);
            },
          },
          child: Focus(
            autofocus: true,
            child: PopScope(
              canPop: !_fullscreen,
              onPopInvokedWithResult: (didPop, result) {
                if (!didPop && _fullscreen) _setFullscreen(false);
              },
              child: Scaffold(
                body: SafeArea(
                  child: Column(
                    children: [
                      AnimatedSize(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeInOutCubic,
                        alignment: Alignment.topCenter,
                        child:
                            _fullscreen
                                ? const SizedBox(width: double.infinity)
                                : Column(
                                  children: [
                                    if (_busy && !_listening)
                                      const LinearProgressIndicator(
                                        minHeight: 2,
                                      ),
                                    _sourceSelector(),
                                    if (desktop) _sourceBar(desktop),
                                    if (!desktop) _mobileNavigation(),
                                  ],
                                ),
                      ),
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (desktop && !_fullscreen)
                              SizedBox(width: 218, child: _tree()),
                            Expanded(child: _workspace()),
                            if (wide && _showInspector && !_fullscreen)
                              SizedBox(width: 280, child: _inspector()),
                          ],
                        ),
                      ),
                      if (!wide &&
                          _showInspector &&
                          _data != null &&
                          !_fullscreen)
                        _compactInspector(),
                      if (!_fullscreen)
                        AnimatedBuilder(
                          animation: _clock,
                          builder: (_, _) => _compactTransport(),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _sourceSelector() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
    child: Row(
      children: [
        Expanded(
          child: _sourceOption(
            AnalysisSource.microphone,
            'Microphone',
            'Live stats',
            Icons.mic_none,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _sourceOption(
            AnalysisSource.file,
            'Audio file',
            'Windowed stats',
            Icons.audio_file_outlined,
          ),
        ),
      ],
    ),
  );

  Widget _sourceOption(
    AnalysisSource source,
    String title,
    String description,
    IconData icon,
  ) {
    final selected = _sourceMode == source;
    final colors = ThemeColors.of(context);
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color:
            selected
                ? Theme.of(context).colorScheme.surfaceContainer
                : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
          side: BorderSide(
            color:
                selected
                    ? colors.textColor.withValues(alpha: .6)
                    : Theme.of(context).dividerColor,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(28),
          onTap:
              _switchingSource || (_busy && !_listening)
                  ? null
                  : () => _selectSource(source),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Row(
              children: [
                Icon(icon, size: 20, color: colors.textColor),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 17),
                      ),
                      Text(
                        description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: colors.textColor.withValues(alpha: .65),
                        ),
                      ),
                    ],
                  ),
                ),
                if (selected)
                  Icon(Icons.check, size: 14, color: colors.textColor),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sourceBar(bool desktop) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
    ),
    child: Row(
      children: [
        Icon(
          _listening ? Icons.mic : Icons.audio_file_outlined,
          size: 16,
          color: ThemeColors.of(context).textColor,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            _source,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 15),
          ),
        ),
        if (desktop && _data != null)
          Text(
            '${_data!.sampleRate} Hz / MONO / ${_data!.frames.length} FRAMES',
            style: _mono,
          ),
        const SizedBox(width: 12),
        _tag(
          _listening
              ? 'LIVE'
              : _busy
              ? 'COMPUTING'
              : _sourceMode == AnalysisSource.microphone
              ? 'PAUSED'
              : 'WINDOWED',
        ),
      ],
    ),
  );

  Widget _tree() => Container(
    decoration: BoxDecoration(
      border: Border(right: BorderSide(color: Theme.of(context).dividerColor)),
    ),
    child: ListView(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 0, 14),
          child: Text('ANALYSIS TREE', style: _mono),
        ),
        for (final section in sections) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 14, 0, 6),
            child: Text(
              '${sections.indexOf(section) + 1}. ${section.toUpperCase()}',
              style: _mono,
            ),
          ),
          for (final tool in tools.where((t) => t.section == section))
            ListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              selected: tool == _tool,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              selectedTileColor: ThemeColors.of(
                context,
              ).flanks.withValues(alpha: 0.3),
              selectedColor: ThemeColors.of(context).textColor,
              leading: Icon(
                tool == _tool
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 13,
              ),
              title: Text(tool.title, style: const TextStyle(fontSize: 16)),
              onTap: () => setState(() => _tool = tool),
            ),
        ],
      ],
    ),
  );

  Widget _mobileNavigation() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
    child: Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            key: ValueKey(_tool.section),
            initialValue: _tool.section,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Section',
              isDense: true,
            ),
            items:
                sections
                    .map(
                      (s) => DropdownMenuItem(
                        value: s,
                        child: Text(s, style: const TextStyle(fontSize: 15)),
                      ),
                    )
                    .toList(),
            onChanged:
                (s) => setState(
                  () => _tool = tools.firstWhere((t) => t.section == s),
                ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: DropdownButtonFormField<String>(
            key: ValueKey(_tool.id),
            initialValue: _tool.id,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Tool', isDense: true),
            items:
                tools
                    .where((t) => t.section == _tool.section)
                    .map(
                      (t) => DropdownMenuItem(
                        value: t.id,
                        child: Text(
                          t.title,
                          style: const TextStyle(fontSize: 15),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
            onChanged:
                (id) =>
                    setState(() => _tool = tools.firstWhere((t) => t.id == id)),
          ),
        ),
      ],
    ),
  );

  void _setFullscreen(bool value) {
    setState(() => _fullscreen = value);
    SystemChrome.setEnabledSystemUIMode(
      value ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
  }

  Widget _compactTransport() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    child: Row(
      children: [
        ShirrDisc(
          asset: Constants.pathIconBtnDisk,
          tooltip: 'Import audio',
          size: 40,
          onPressed: _busy ? null : _import,
        ),
        const SizedBox(width: 8),
        Text(_cursor.toStringAsFixed(1), style: _mono),
        Expanded(
          child: Slider(
            value: _cursor.clamp(0.0, max(.01, _data?.duration ?? 0)),
            max: max(.01, _data?.duration ?? 0),
            onChanged:
                _listening
                    ? null
                    : (v) {
                      setState(() {
                        _scrubbing = true;
                        _cursor = v;
                      });
                    },
            onChangeEnd: _listening ? null : _inspect,
          ),
        ),
        ShirrDisc(
          asset:
              Theme.of(context).brightness == Brightness.dark
                  ? Constants.pathIconPlayDark
                  : Constants.pathIconPlayLight,
          tooltip: _playing || _listening ? 'Pause' : 'Play',
          size: 52,
          onPressed: _play,
        ),
      ],
    ),
  );

  Widget _workspace() => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _tool.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            IconButton(
              tooltip: 'Choose analysis tool',
              icon: const Icon(Icons.grid_view_outlined),
              onPressed: _chooseTool,
            ),
            TextButton(onPressed: _maths, child: const Text('Maths')),
            IconButton(
              tooltip: 'Analysis details',
              icon: const Icon(Icons.tune),
              onPressed: () {
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  builder:
                      (_) => AnimatedBuilder(
                        animation: _changes,
                        builder:
                            (_, _) => SizedBox(
                              height: MediaQuery.sizeOf(context).height * .85,
                              child: _details(),
                            ),
                      ),
                );
              },
            ),
            IconButton(
              tooltip: _fullscreen ? 'Exit fullscreen' : 'Fullscreen graph',
              icon: Icon(
                _fullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
              ),
              onPressed: () => _setFullscreen(!_fullscreen),
            ),
          ],
        ),
      ),
      if (_data != null &&
          (_timeline || _tool.id == 'spectrum' || _tool.id == 'pca'))
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              const Spacer(),
              if (_timeline)
                FilterChip(
                  label: const Text('Follow', style: TextStyle(fontSize: 12)),
                  selected: _follow,
                  onSelected: (v) => setState(() => _follow = v),
                ),
              IconButton(
                tooltip: 'Zoom in',
                icon: const Icon(Icons.add),
                onPressed: () => _zoom(.7),
              ),
              IconButton(
                tooltip: 'Zoom out',
                icon: const Icon(Icons.remove),
                onPressed: () => _zoom(1.4),
              ),
            ],
          ),
        ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _source,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11),
              ),
            ),
            Text(
              _listening
                  ? 'LIVE'
                  : _sourceMode == AnalysisSource.file
                  ? 'WINDOWED'
                  : 'PAUSED',
              style: const TextStyle(fontSize: 10),
            ),
          ],
        ),
      ),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: RepaintBoundary(
            child:
                _data == null
                    ? Center(
                      child: Text(
                        _listening
                            ? 'Listening…'
                            : 'Choose an audio file or microphone',
                      ),
                    )
                    : AnimatedBuilder(
                      animation: _clock,
                      builder: (_, _) => ShirrPlotFrame(child: _plot()),
                    ),
          ),
        ),
      ),
      if (_data != null) _plotLegend(),
      if (_tool.id == 'beats' && _data != null)
        AnimatedBuilder(animation: _clock, builder: (_, _) => _beatStatus()),
      if (_fullscreen)
        AnimatedBuilder(
          animation: _clock,
          builder: (_, _) => _compactTransport(),
        ),
    ],
  );

  Widget _plotLegend() {
    final captions = <String, String>{
      'beats':
          'Signed PLP pulse · vertical markers are beat triggers · lookahead is predictive',
      'waveform':
          'Smoothed amplitude envelope · display only · raw PCM preserved',
      'chroma':
          'Pitch-class radar · radius scaled to the strongest class in this frame',
      'cqt': 'C2–B8 octave-folded energy · twelve pitch classes · 0–1',
      'mfcc': 'Five signed cepstral coefficients at the playback cursor',
      'summary': 'Histogram of frame RMS · selected interval · 16 bins',
      'tempo': 'Candidate BPM / normalized onset autocorrelation',
      'pca': 'Each point is one frame · standardized descriptor PCA',
      'correlation':
          'Axes: RMS, centroid, spread, entropy, flatness, roll-off, flux, ZCR',
      'similarity': 'Chroma cosine similarity · 0 unrelated → 1 similar',
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 5),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_tool.id == 'spectrogram' || _tool.id == 'correlation') ...[
            Container(
              height: 8,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                gradient: LinearGradient(
                  colors:
                      _tool.id == 'spectrogram'
                          ? spectrogramPalette
                          : const [inkBlue, Color(0xFF17202C), inkAmber],
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children:
                  _tool.id == 'spectrogram'
                      ? const [
                        Text('−100 dB', style: TextStyle(fontSize: 10)),
                        Text('−30 dB', style: TextStyle(fontSize: 10)),
                        Text('+40 dB', style: TextStyle(fontSize: 10)),
                      ]
                      : const [
                        Text('−1', style: TextStyle(fontSize: 10)),
                        Text('0', style: TextStyle(fontSize: 10)),
                        Text('+1', style: TextStyle(fontSize: 10)),
                      ],
            ),
          ],
          Text(
            _tool.id == 'spectrogram'
                ? 'STFT magnitude · logarithmic dB scale · relative transform level'
                : captions[_tool.id] ?? '${_tool.title} · ${_tool.units}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _details() => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Text(
        '${_tool.section.toUpperCase()} / ${_tool.id.toUpperCase()}',
        style: _mono,
      ),
      AnimatedBuilder(animation: _clock, builder: (_, _) => _transport()),
      const SizedBox(height: 8),
      Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 16,
        runSpacing: 8,
        children: [
          Text(
            _tool.title,
            style: Theme.of(
              context,
            ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(shape: const StadiumBorder()),
            onPressed: _maths,
            icon: const Text('∑', style: TextStyle(fontSize: 20)),
            label: const Text('Maths'),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Text(
        _tool.subtitle,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
        ),
      ),
      const SizedBox(height: 20),
      if (_data == null)
        SizedBox(
          height: 300,
          child: Center(
            child: Text(
              _sourceMode == AnalysisSource.microphone
                  ? 'Listening… live statistics appear as samples arrive.'
                  : 'Choose an audio file to inspect its analysis windows.',
            ),
          ),
        )
      else ...[
        _plotToolbar(),
        const SizedBox(height: 12),
        if (_tool.id == 'frame')
          _inspectorContent()
        else if (_tool.id == 'gain')
          _gainPanel()
        else
          SizedBox(
            height: MediaQuery.sizeOf(context).width < 760 ? 260 : 340,
            child: AnimatedBuilder(
              animation: _clock,
              builder: (_, _) => ShirrPlotFrame(child: _plot()),
            ),
          ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            _tag(_tool.units),
            _tag('HANN ${_data!.window} / HOP ${_data!.hop}'),
            if (_tool.id == 'tempo' || _tool.section == 'Structure')
              _tag('EXPLORATORY'),
          ],
        ),
        const SizedBox(height: 20),
        if (_tool.id == 'pca') _pcaDetails(),
        if (_tool.id == 'correlation')
          Text(
            'Axis order: ${featureNames.join(' · ')}\nBlue: negative correlation. Amber: positive. Constant columns: zero.',
            style: const TextStyle(fontSize: 12, height: 1.7),
          ),
        if (_tool.id == 'chroma')
          const Text(
            'Radar axes are pitch classes C through B; radius is relative to the strongest class in the selected frame.',
            style: TextStyle(fontSize: 12),
          ),
        if (_tool.id == 'mfcc')
          const Text(
            'Signed coefficient bars c₀ through c₄ are measured in the selected analysis frame.',
            style: TextStyle(fontSize: 12),
          ),
        if (_tool.id == 'beats') _beatControls(),
        if (_tool.id == 'tempo') _tempoDetails(),
        if (_tool.id == 'summary') _summary(),
        if (_tool.section == 'Structure') _structureDetails(),
        const SizedBox(height: 16),
        _markers(),
      ],
    ],
  );

  bool get _timeline =>
      ![
        'spectrum',
        'cqt',
        'chroma',
        'mfcc',
        'pca',
        'correlation',
        'summary',
        'tempo',
        'frame',
        'gain',
      ].contains(_tool.id);
  Widget _plotToolbar() => Wrap(
    spacing: 6,
    runSpacing: 6,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      if (_timeline)
        TextButton.icon(
          icon: const Icon(Icons.crop, size: 18),
          label: const Text('Select interval'),
          onPressed: () {
            setState(() {
              _mode = 'Range';
              _follow = false;
            });
            Navigator.pop(context);
          },
        ),
      if (_timeline || _tool.id == 'spectrum' || _tool.id == 'pca') ...[
        IconButton(
          tooltip: 'Zoom in',
          onPressed: () => _zoom(0.7),
          icon: const Icon(Icons.add, size: 18),
        ),
        IconButton(
          tooltip: 'Zoom out',
          onPressed: () => _zoom(1.4),
          icon: const Icon(Icons.remove, size: 18),
        ),
        TextButton(
          onPressed:
              () => setState(() {
                _viewStart = 0;
                _viewEnd = _data!.duration;
                _frequencyStart = 0;
                _frequencyEnd = 11025;
                _pcaMinX = _pcaMaxX = _pcaMinY = _pcaMaxY = null;
              }),
          child: const Text('Reset'),
        ),
      ],
      if (_timeline)
        TextButton(
          onPressed:
              () => setState(() {
                _viewStart = _rangeStart;
                _viewEnd = max(_rangeStart + 0.01, _rangeEnd);
              }),
          child: const Text('Fit range'),
        ),
    ],
  );

  void _zoom(double factor, [double? anchor]) => setState(() {
    if (_tool.id == 'pca') {
      final scores = _data!.scores;
      if (scores.isEmpty) return;
      final lo = _pcaMinX ?? scores.map((p) => p[0]).reduce(min) - 0.5;
      final hi = _pcaMaxX ?? scores.map((p) => p[0]).reduce(max) + 0.5;
      final bottom = _pcaMinY ?? scores.map((p) => p[1]).reduce(min) - 0.5;
      final top = _pcaMaxY ?? scores.map((p) => p[1]).reduce(max) + 0.5;
      final x = anchor ?? (lo + hi) / 2;
      _pcaMinX = x - (x - lo) * factor;
      _pcaMaxX = x + (hi - x) * factor;
      final mid = (bottom + top) / 2;
      _pcaMinY = mid - (top - bottom) * factor / 2;
      _pcaMaxY = mid + (top - bottom) * factor / 2;
      return;
    }
    final spectrum = _tool.id == 'spectrum';
    final lo = spectrum ? _frequencyStart : _viewStart,
        hi = spectrum ? _frequencyEnd : _viewEnd;
    final cap = spectrum ? 11025.0 : _data!.duration;
    final center = anchor ?? (spectrum ? (lo + hi) / 2 : _cursor.clamp(lo, hi));
    final width =
        ((hi - lo) * factor)
            .clamp(spectrum ? 20.0 : 0.05, max(spectrum ? 20.0 : 0.05, cap))
            .toDouble();
    final left =
        (center - (center - lo) / max(1e-12, hi - lo) * width)
            .clamp(0.0, max(0.0, cap - width))
            .toDouble();
    if (spectrum) {
      _frequencyStart = left;
      _frequencyEnd = left + width;
    } else {
      _viewStart = left;
      _viewEnd = left + width;
    }
  });

  Future<void> _requestPitch() async {
    if (!Platform.isAndroid ||
        _pitchBusy ||
        (_cursor - _pitchTime).abs() < .1) {
      return;
    }
    _pitchBusy = true;
    final time = _cursor;
    final generation = _generation;
    try {
      final bins = await _worker.pitch(time);
      if (!mounted || generation != _generation) return;
      _pitchBins = bins;
      _pitchTime = time;
      _clock.value++;
    } catch (_) {
      _pitchTime = time;
    } finally {
      _pitchBusy = false;
    }
  }

  Widget _plot() {
    final d = _data!;
    if (_follow && _timeline && !_listening) {
      final width = min(d.duration, max(.05, _viewEnd - _viewStart));
      _viewStart = (_cursor - width * .5).clamp(
        0.0,
        max(0.0, d.duration - width),
      );
      _viewEnd = _viewStart + width;
    }
    final f = d.frames.isEmpty ? null : d.frames[d.nearest(_cursor)];
    List<Offset> points = [];
    List<List<double>>? matrix;
    String xLabel = 'time / s', yLabel = _tool.units;
    double minX = _viewStart, maxX = _viewEnd;
    bool scatter = false, signed = false;
    final visible =
        d.frames.isEmpty
            ? <AnalysisFrame>[]
            : d.frames.sublist(
              d.nearest(_viewStart),
              min(d.frames.length, d.nearest(_viewEnd) + 1),
            );
    switch (_tool.id) {
      case 'waveform':
        final first = (_viewStart * d.sampleRate / 64).floor().clamp(
          0,
          d.envelopeLow.length,
        );
        final end = (_viewEnd * d.sampleRate / 64).ceil().clamp(
          first,
          d.envelopeLow.length,
        );
        final step = max(1, ((end - first) / 800).ceil());
        for (int i = first; i < end; i += step) {
          double low = d.envelopeLow[i], high = d.envelopeHigh[i];
          for (int j = i + 1; j < min(end, i + step); j++) {
            low = min(low, d.envelopeLow[j]);
            high = max(high, d.envelopeHigh[j]);
          }
          if (end - first > 200) {
            double smoothLow = 0, smoothHigh = 0;
            int count = 0;
            for (int j = max(first, i - 2); j < min(end, i + 3); j++) {
              smoothLow += d.envelopeLow[j];
              smoothHigh += d.envelopeHigh[j];
              count++;
            }
            low = smoothLow / count;
            high = smoothHigh / count;
          }
          points.add(Offset(i * 64 / d.sampleRate, low));
          points.add(Offset(i * 64 / d.sampleRate, high));
        }
        break;
      case 'beats':
        if (!_listening && _beatData != d && !_beatBusy) _requestBeats();
        points = [
          for (int i = 0; i < d.beats.times.length; i++)
            Offset(d.beats.times[i], d.beats.pulse[i]),
        ];
        yLabel = 'signed PLP pulse';
        break;
      case 'cqt':
        if (_sourceMode == AnalysisSource.file) _requestPitch();
        final bins =
            _sourceMode == AnalysisSource.file
                ? _pitchBins
                : (f?.cqt ?? const <double>[]);
        final chroma = List.filled(12, 0.0);
        for (int i = 0; i < bins.length; i++) {
          chroma[i % 12] += bins[i] * bins[i];
        }
        final total = chroma.fold(0.0, (a, b) => a + b);
        points = List.generate(
          12,
          (i) => Offset(i.toDouble(), total > 1e-16 ? chroma[i] / total : 0),
        );
        minX = -.5;
        maxX = 11.5;
        xLabel = 'pitch class';
        yLabel =
            bins.isEmpty
                ? Platform.isAndroid
                    ? 'Preparing ECQT…'
                    : 'ECQT available on Android'
                : total < 1e-16
                ? 'Silence'
                : 'Dominant ${const ['C', 'C♯', 'D', 'D♯', 'E', 'F', 'F♯', 'G', 'G♯', 'A', 'A♯', 'B'][chroma.indexOf(chroma.reduce(max))]} · ECQT energy';
        break;
      case 'spectrum':
        points = List.generate(
          f?.spectrum.length ?? 0,
          (i) => Offset(i * d.sampleRate / d.window, f!.spectrum[i]),
        );
        minX = _frequencyStart;
        maxX = _frequencyEnd;
        xLabel = 'frequency / Hz';
        break;
      case 'spectrogram':
        final selected = _thin(visible, 240);
        matrix = List.generate(
          96,
          (row) =>
              selected.map((frame) {
                final k =
                    ((95 - row) * (frame.spectrum.length - 1) / 95).round();
                return (20 * log(max(frame.spectrum[k], 1e-12)) / ln10).clamp(
                  -100.0,
                  40.0,
                );
              }).toList(),
        );
        yLabel = 'frequency ↑ 0–11,025 Hz';
        break;
      case 'chroma':
        points = List.generate(
          12,
          (i) => Offset(i.toDouble(), f?.chroma[i] ?? 0),
        );
        minX = -.5;
        maxX = 11.5;
        xLabel = 'pitch class';
        yLabel = 'relative energy';
        break;
      case 'mfcc':
        points = List.generate(5, (i) => Offset(i.toDouble(), f?.mfcc[i] ?? 0));
        minX = -.5;
        maxX = 4.5;
        xLabel = 'coefficient';
        yLabel = 'MFCC value';
        break;
      case 'correlation':
        matrix = d.correlation;
        signed = true;
        minX = 0;
        maxX = 8;
        xLabel = 'descriptor index';
        yLabel = 'descriptor index';
        break;
      case 'pca':
        points = d.scores.map((score) => Offset(score[0], score[1])).toList();
        scatter = true;
        minX = points.isEmpty ? -1 : points.map((p) => p.dx).reduce(min) - 0.5;
        maxX = points.isEmpty ? 1 : points.map((p) => p.dx).reduce(max) + 0.5;
        xLabel = 'PC1 score';
        yLabel = 'PC2 score';
        break;
      case 'similarity':
        final indices =
            List.generate(d.structureTimes.length, (i) => i)
                .where(
                  (i) =>
                      d.structureTimes[i] >= _viewStart &&
                      d.structureTimes[i] <= _viewEnd,
                )
                .toList();
        matrix =
            indices
                .map((i) => indices.map((j) => d.similarity[i][j]).toList())
                .toList();
        yLabel = 'time / s (top → bottom)';
        break;
      case 'novelty':
        points = List.generate(
          d.novelty.length,
          (i) => Offset(d.structureTimes[i], d.novelty[i]),
        );
        break;
      case 'tempo':
        points =
            d.tempo.map((p) => Offset(p[0], p[1])).toList()
              ..sort((a, b) => a.dx.compareTo(b.dx));
        minX = 40;
        maxX = 240;
        xLabel = 'tempo / BPM';
        yLabel = 'autocorrelation';
        break;
      case 'summary':
        final values =
            d.frames
                .where(
                  (frame) =>
                      frame.time >= _rangeStart && frame.time <= _rangeEnd,
                )
                .map((f) => f.values[0])
                .toList();
        if (values.isNotEmpty) {
          minX = values.reduce(min);
          maxX = max(minX + 1e-6, values.reduce(max));
          final counts = List.filled(16, 0.0);
          for (final v in values) {
            counts[((v - minX) / (maxX - minX) * 16).floor().clamp(0, 15)]++;
          }
          points = List.generate(
            16,
            (i) => Offset(minX + (maxX - minX) * (i + 0.5) / 16, counts[i]),
          );
        } else {
          minX = 0;
          maxX = 1;
        }
        xLabel = 'RMS amplitude';
        yLabel = 'frame count';
        break;
      default:
        if (featureNames.contains(_tool.id)) {
          points =
              visible.map((f) => Offset(f.time, f.feature(_tool.id))).toList();
        }
    }
    final spectrum = _tool.id == 'spectrum', pca = _tool.id == 'pca';
    final activePins =
        _pins
            .where(
              (p) => spectrum ? p['frequency'] != null : p['frequency'] == null,
            )
            .toList();
    double? minY, maxY;
    if (_tool.id == 'cqt') {
      minY = 0;
      maxY = 1;
    }
    if (pca && points.isNotEmpty) {
      minX = _pcaMinX ?? minX;
      maxX = _pcaMaxX ?? maxX;
      minY = _pcaMinY ?? points.map((p) => p.dy).reduce(min) - 0.5;
      maxY = _pcaMaxY ?? points.map((p) => p.dy).reduce(max) + 0.5;
    }
    return ScientificPlot(
      bars: ['cqt', 'mfcc', 'summary', 'tempo'].contains(_tool.id),
      radar: _tool.id == 'chroma',
      envelope: _tool.id == 'waveform',
      spectrogram: _tool.id == 'spectrogram',
      tickLabels:
          ['cqt', 'chroma'].contains(_tool.id)
              ? const [
                'C',
                'C♯',
                'D',
                'D♯',
                'E',
                'F',
                'F♯',
                'G',
                'G♯',
                'A',
                'A♯',
                'B',
              ]
              : _tool.id == 'mfcc'
              ? const ['c₀', 'c₁', 'c₂', 'c₃', 'c₄']
              : const [],
      colorMin:
          _tool.id == 'spectrogram'
              ? -100
              : ['chroma', 'similarity'].contains(_tool.id)
              ? 0
              : null,
      colorMax:
          _tool.id == 'spectrogram'
              ? 40
              : ['chroma', 'similarity'].contains(_tool.id)
              ? 1
              : null,
      minY: minY,
      maxY: maxY,
      onZoom:
          _timeline || spectrum || pca
              ? (factor, anchor) {
                _follow = false;
                _zoom(factor, anchor);
              }
              : null,
      onMovePin:
          (index, value) => setState(
            () => activePins[index][spectrum ? 'frequency' : 'time'] = value,
          ),
      onPan2D:
          pca
              ? (x, y) => setState(() {
                _pcaMinX = minX + x;
                _pcaMaxX = maxX + x;
                _pcaMinY = minY! + y;
                _pcaMaxY = maxY! + y;
              })
              : null,
      points: points,
      matrix: matrix,
      scatter: scatter,
      signed: signed,
      xLabel: xLabel,
      yLabel: yLabel,
      minX: minX,
      maxX: max(minX + 1e-6, maxX),
      cursor:
          _timeline
              ? _cursor
              : spectrum
              ? _frequencyCursor
              : null,
      rangeStart: _timeline ? _rangeStart : null,
      rangeEnd: _timeline ? _rangeEnd : null,
      pins:
          _tool.id == 'beats'
              ? d.beats.events
              : _timeline || spectrum
              ? activePins
                  .map((p) => p[spectrum ? 'frequency' : 'time'] as double)
                  .toList()
              : [],
      mode: _mode,
      onInspect:
          _timeline
              ? _inspect
              : spectrum
              ? (frequency) {
                setState(() => _frequencyCursor = frequency);
                if (_mode == 'Pin') _editMarker(false, frequency: frequency);
              }
              : null,
      onRangeEnd: () => setState(() => _mode = 'Pan'),
      onRange:
          _timeline
              ? (a, b) => setState(() {
                _rangeStart = a;
                _rangeEnd = b;
              })
              : null,
      onPan:
          _timeline || spectrum
              ? (delta) => setState(() {
                if (spectrum) {
                  final width = _frequencyEnd - _frequencyStart;
                  _frequencyStart = (_frequencyStart + delta).clamp(
                    0.0,
                    11025.0 - width,
                  );
                  _frequencyEnd = _frequencyStart + width;
                  return;
                }
                _follow = false;
                final width = _viewEnd - _viewStart;
                _viewStart = (_viewStart + delta).clamp(
                  0.0,
                  max(0.0, d.duration - width),
                );
                _viewEnd = _viewStart + width;
              })
              : null,
    );
  }

  List<AnalysisFrame> _thin(List<AnalysisFrame> frames, int limit) =>
      frames.length <= limit
          ? frames
          : List.generate(
            limit,
            (i) => frames[(i * (frames.length - 1) / (limit - 1)).round()],
          );

  Widget _inspector() => Container(
    decoration: BoxDecoration(
      border: Border(left: BorderSide(color: Theme.of(context).dividerColor)),
    ),
    child: ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Text('FRAME INSPECTOR', style: _mono),
        const SizedBox(height: 20),
        _inspectorContent(),
      ],
    ),
  );
  Widget _inspectorContent() {
    final d = _data;
    if (d == null || d.frames.isEmpty) return const Text('No frame selected.');
    final index = d.nearest(_cursor), f = d.frames[d.nearest(_cursor)];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${f.time.toStringAsFixed(3)} s',
          style: const TextStyle(fontFamily: 'monospace', fontSize: 26),
        ),
        const SizedBox(height: 6),
        Text(
          'FRAME ${index.toString().padLeft(4, '0')} · ${f.values[0] < 1e-12 ? 'SILENCE' : 'SIGNAL'}',
          style: _mono,
        ),
        const SizedBox(height: 20),
        for (int i = 0; i < featureNames.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    featureNames[i],
                    style: const TextStyle(fontSize: 15),
                  ),
                ),
                Text(
                  f.values[i].toStringAsPrecision(5),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
                const SizedBox(width: 8),
                Text(
                  ['amp', 'Hz', 'Hz', '0–1', '0–1', 'Hz', 'Δ', '/sample'][i],
                  style: _mono,
                ),
              ],
            ),
          ),
        const Divider(height: 28),
        Text('ANALYSIS PARAMETERS', style: _mono),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          initialValue: _window,
          decoration: const InputDecoration(
            labelText: 'Hann window / samples',
            isDense: true,
          ),
          items:
              [512, 1024, 2048]
                  .map((n) => DropdownMenuItem(value: n, child: Text('$n')))
                  .toList(),
          onChanged:
              _busy || _listening
                  ? null
                  : (n) {
                    setState(() => _window = n!);
                    _analyze(d.samples, d.sampleRate, reset: false);
                  },
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          initialValue: _hop,
          decoration: const InputDecoration(
            labelText: 'Requested hop / samples',
            isDense: true,
          ),
          items:
              [256, 512, 1024]
                  .map((n) => DropdownMenuItem(value: n, child: Text('$n')))
                  .toList(),
          onChanged:
              _busy || _listening
                  ? null
                  : (n) {
                    setState(() => _hop = n!);
                    _analyze(d.samples, d.sampleRate, reset: false);
                  },
        ),
        const SizedBox(height: 12),
        Text(
          'Δf = ${(d.sampleRate / d.window).toStringAsFixed(2)} Hz\nΔt = ${(1000 * d.hop / d.sampleRate).toStringAsFixed(2)} ms\nActual hop ${d.hop} · ≤6,000 frames\nMono 22,050 Hz · local Dart isolate',
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 11,
            height: 1.8,
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Silence conventions, resampling limits and measurement definitions are documented in Maths.',
          style: TextStyle(fontSize: 11, height: 1.6),
        ),
      ],
    );
  }

  Widget _compactInspector() {
    final d = _data!;
    final f = d.frames.isEmpty ? null : d.frames[d.nearest(_cursor)];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'FRAME ${d.nearest(_cursor)}  ·  RMS ${f?.values[0].toStringAsFixed(4) ?? '—'}  ·  ${f?.values[1].toStringAsFixed(0) ?? '—'} Hz',
              style: const TextStyle(fontFamily: 'monospace', fontSize: 10),
            ),
          ),
          TextButton(
            onPressed:
                () => setState(
                  () => _tool = tools.firstWhere((t) => t.id == 'frame'),
                ),
            child: const Text('Inspect'),
          ),
        ],
      ),
    );
  }

  void _updateDiscMotion() {
    if (_playing || _listening) {
      _discMotion.repeat();
    } else {
      _discMotion.stop();
    }
  }

  Widget _transport() {
    final duration = _data?.duration ?? 0;
    final colors = ThemeColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Text(_cursor.toStringAsFixed(2), style: _mono),
                Expanded(
                  child: Slider(
                    key: const ValueKey('details-playback'),
                    value: _cursor.clamp(0.0, max(.01, duration)),
                    max: max(.01, duration),
                    onChanged:
                        _listening || _busy
                            ? null
                            : (v) => setState(() {
                              _scrubbing = true;
                              _cursor = v;
                            }),
                    onChangeEnd: _listening ? null : _inspect,
                  ),
                ),
                Text('${duration.toStringAsFixed(2)} s', style: _mono),
              ],
            ),
          ),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: ShirrBranch(
                  fromLeft: true,
                  children: [
                    ShirrDisc(
                      asset: Constants.pathIconBtnSave,
                      tooltip: 'Export analysis JSON',
                      size: 44,
                      onPressed: _data == null || _busy ? null : _export,
                    ),
                    ShirrDisc(
                      asset: Constants.pathIconBtnMic,
                      tooltip: 'Capture microphone',
                      size: 44,
                      selected: _listening,
                      onPressed:
                          _busy
                              ? null
                              : () async {
                                await _toggleMic();
                                _updateDiscMotion();
                              },
                    ),
                    ShirrDisc(
                      asset: Constants.pathIconBtnDisk,
                      tooltip: 'Import audio',
                      size: 44,
                      onPressed: _busy ? null : _import,
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 2,
                child: Center(
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow:
                          _playing || _listening
                              ? [
                                BoxShadow(
                                  color: colors.textColor.withValues(
                                    alpha: .35,
                                  ),
                                  blurRadius: 18,
                                ),
                              ]
                              : [],
                    ),
                    child: RotationTransition(
                      turns: _discMotion,
                      child: ShirrDisc(
                        asset:
                            Theme.of(context).brightness == Brightness.dark
                                ? Constants.pathIconPlayLight
                                : Constants.pathIconPlayDark,
                        tooltip: _playing || _listening ? 'Pause' : 'Play',
                        size: 64,
                        onPressed:
                            _busy
                                ? null
                                : () async {
                                  await _play();
                                  _updateDiscMotion();
                                },
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Wrap(
              spacing: 16,
              children: [
                Text(
                  'RANGE ${_rangeStart.toStringAsFixed(2)}–${_rangeEnd.toStringAsFixed(2)} s',
                  style: _mono,
                ),
                Text(
                  'N=${_data?.window ?? _window} H=${_data?.hop ?? _hop}',
                  style: _mono,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _chooseTool() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder:
          (context) => DraggableScrollableSheet(
            expand: false,
            initialChildSize: .7,
            maxChildSize: .95,
            builder:
                (context, scroll) => ListView(
                  controller: scroll,
                  padding: const EdgeInsets.all(24),
                  children: [
                    Text(
                      'Choose a tool',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        TextButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            _demo();
                          },
                          icon: const Icon(Icons.science_outlined),
                          label: const Text('Demo recording'),
                        ),
                        TextButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            setState(() => _showInspector = !_showInspector);
                          },
                          icon: const Icon(Icons.visibility_outlined),
                          label: const Text('Frame inspector'),
                        ),
                      ],
                    ),
                    for (final section in sections) ...[
                      const SizedBox(height: 18),
                      Text(
                        section,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      for (final tool in tools.where(
                        (t) => t.section == section,
                      ))
                        ListTile(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                          selected: tool.id == _tool.id,
                          title: Text(tool.title),
                          subtitle: Text(tool.subtitle),
                          onTap: () {
                            Navigator.pop(context);
                            setState(() => _tool = tool);
                          },
                        ),
                    ],
                  ],
                ),
          ),
    );
  }

  Widget _pcaDetails() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Explained variance · PC1 ${(_data!.explained[0] * 100).toStringAsFixed(1)}% · PC2 ${(_data!.explained[1] * 100).toStringAsFixed(1)}%',
        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
      ),
      const SizedBox(height: 12),
      _table(
        ['Descriptor', 'PC1 loading', 'PC2 loading'],
        List.generate(
          8,
          (i) => [
            featureNames[i],
            _data!.loadings[0][i].toStringAsFixed(3),
            _data!.loadings[1][i].toStringAsFixed(3),
          ],
        ),
      ),
    ],
  );
  Widget _tempoDetails() {
    final candidates = List<List<double>>.from(_data!.tempo)
      ..sort((a, b) => b[1].compareTo(a[1]));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          candidates.isEmpty
              ? 'No tempo candidates: insufficient onset variation.'
              : 'Highest autocorrelation candidates (neighboring lags may describe the same peak).',
          style: const TextStyle(fontSize: 12, height: 1.6),
        ),
        if (candidates.isNotEmpty)
          _table(
            ['BPM', 'Score'],
            candidates
                .take(5)
                .map((c) => [c[0].toStringAsFixed(1), c[1].toStringAsFixed(3)])
                .toList(),
          ),
      ],
    );
  }

  Widget _summary() {
    final frames =
        _data!.frames
            .where((f) => f.time >= _rangeStart && f.time <= _rangeEnd)
            .toList();
    if (frames.isEmpty) {
      return const Text('No frame centers inside this interval.');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${frames.length} frames in selected interval', style: _mono),
        const SizedBox(height: 12),
        _table(
          ['Feature', 'Mean', 'SD', 'Min', 'Max'],
          List.generate(8, (i) {
            final values = frames.map((f) => f.values[i]).toList();
            final mean = values.reduce((a, b) => a + b) / values.length;
            final sd =
                values.length < 2
                    ? 0.0
                    : sqrt(
                      values.fold(0.0, (s, v) => s + pow(v - mean, 2)) /
                          (values.length - 1),
                    );
            return [
              featureNames[i],
              mean.toStringAsPrecision(4),
              sd.toStringAsPrecision(4),
              values.reduce(min).toStringAsPrecision(4),
              values.reduce(max).toStringAsPrecision(4),
            ];
          }),
        ),
      ],
    );
  }

  Widget _structureDetails() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('CANDIDATE BOUNDARIES', style: _mono),
      const SizedBox(height: 10),
      Wrap(
        spacing: 8,
        children:
            _data!.boundaries
                .map(
                  (t) => ActionChip(
                    label: Text('${t.toStringAsFixed(2)} s'),
                    onPressed: () => _inspect(t),
                  ),
                )
                .toList(),
      ),
      if (_data!.boundaries.isEmpty)
        const Text('No peaks exceed the current novelty threshold.'),
      const SizedBox(height: 8),
      TextButton.icon(
        onPressed: () => _editMarker(true),
        icon: const Icon(Icons.edit_note),
        label: const Text('Annotate section at cursor'),
      ),
      for (int i = 0; i < _annotations.length; i++)
        _markerRow(_annotations, i, true),
    ],
  );
  Widget _markers() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Text('SESSION PINS', style: _mono),
          const Spacer(),
          TextButton.icon(
            onPressed:
                _listening
                    ? null
                    : () => _editMarker(
                      false,
                      frequency:
                          _tool.id == 'spectrum' ? _frequencyCursor : null,
                    ),
            icon: const Icon(Icons.push_pin_outlined, size: 14),
            label: const Text('Pin cursor'),
          ),
        ],
      ),
      if (_pins.isEmpty)
        const Text(
          'Pin a moment to revisit it across timeline views.',
          style: TextStyle(fontSize: 12),
        ),
      for (int i = 0; i < _pins.length; i++) _markerRow(_pins, i, false),
    ],
  );
  Widget _markerRow(
    List<Map<String, dynamic>> list,
    int i,
    bool annotation,
  ) => ListTile(
    dense: true,
    contentPadding: EdgeInsets.zero,
    leading: Icon(
      annotation ? Icons.segment : Icons.push_pin_outlined,
      size: 16,
      color: ThemeColors.of(context).textColor,
    ),
    title: Text(
      list[i]['label'] as String,
      style: const TextStyle(fontSize: 15),
    ),
    subtitle: Text(
      '${(list[i]['time'] as double).toStringAsFixed(3)} s${list[i]['frequency'] != null ? ' · ${(list[i]['frequency'] as double).toStringAsFixed(1)} Hz' : ''}',
      style: _mono,
    ),
    onTap: () {
      if (list[i]['frequency'] != null) {
        setState(() => _frequencyCursor = list[i]['frequency'] as double);
      }
      final previous = _mode;
      _mode = 'Inspect';
      _inspect(list[i]['time'] as double);
      _mode = previous;
    },
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Move to cursor',
          onPressed: () => setState(() => list[i]['time'] = _cursor),
          icon: const Icon(Icons.my_location, size: 16),
        ),
        IconButton(
          tooltip: 'Edit label',
          onPressed: () => _editMarker(annotation, index: i),
          icon: const Icon(Icons.edit_outlined, size: 16),
        ),
        IconButton(
          tooltip: 'Delete',
          onPressed: () => setState(() => list.removeAt(i)),
          icon: const Icon(Icons.close, size: 16),
        ),
      ],
    ),
  );
  Widget _gainPanel() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Apply gain to the selected interval, then recompute the same descriptors. The experiment uses floating-point samples without clipping.',
        style: TextStyle(height: 1.6),
      ),
      const SizedBox(height: 16),
      Text('GAIN ×${_gain.toStringAsFixed(2)}', style: _mono),
      Slider(
        key: const ValueKey('gain-slider'),
        value: _gain,
        min: 0.1,
        max: 3,
        onChanged: _busy ? null : (v) => setState(() => _gain = v),
      ),
      FilledButton.icon(
        onPressed: _busy || _listening ? null : _runGain,
        icon: const Icon(Icons.science_outlined),
        label: const Text('Run paired experiment'),
      ),
      const SizedBox(height: 20),
      if (_experiment != null) ...[
        _table(
          ['Measurement', 'Result'],
          _experiment!.entries
              .where((e) => e.key != 'interval')
              .map(
                (e) => [
                  e.key,
                  e.value is double
                      ? (e.value as double).toStringAsPrecision(6)
                      : '${e.value}',
                ],
              )
              .toList(),
        ),
        const SizedBox(height: 12),
        Text(
          'Computed for ${(_experiment!['interval'] as List).join('–')} s. Gain ×${_experiment!['gain']}.',
          style: _mono,
        ),
      ],
    ],
  );
  Widget _table(List<String> headings, List<List<String>> rows) =>
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowHeight: 36,
          dataRowMinHeight: 32,
          dataRowMaxHeight: 36,
          horizontalMargin: 8,
          columnSpacing: 24,
          columns:
              headings
                  .map((s) => DataColumn(label: Text(s, style: _mono)))
                  .toList(),
          rows:
              rows
                  .map(
                    (row) => DataRow(
                      cells:
                          row
                              .map(
                                (s) => DataCell(
                                  Text(
                                    s,
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                    ),
                  )
                  .toList(),
        ),
      );
}
