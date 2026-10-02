import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../../music/cellular_music.dart';
import '../../music/maths_sheet.dart';

class AudioGeneratorScreen extends StatefulWidget {
  const AudioGeneratorScreen({super.key});
  @override
  State<AudioGeneratorScreen> createState() => _AudioGeneratorScreenState();
}

class _AudioGeneratorScreenState extends State<AudioGeneratorScreen>
    with WidgetsBindingObserver {
  final _player = AudioPlayer();
  final _step = ValueNotifier<int>(0);
  final _subscriptions = <StreamSubscription>[];
  List<int> _seed = List.generate(32, (i) => i == 16 ? 1 : 0);
  int _rule = 30;
  double _bpm = 110;
  String _scale = 'Minor pentatonic', _error = '';
  bool _busy = false, _playing = false, _dirty = true, _loop = true;
  Uint8List? _wav;
  String? _path;
  File? _temporary;
  late CellularScore _score;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _rebuild();
    _subscriptions.add(
      _player.onPositionChanged.listen((p) {
        _step.value = (p.inMilliseconds / 1000 / _score.stepSeconds)
            .floor()
            .clamp(0, _score.rows.length - 1);
      }),
    );
    _subscriptions.add(
      _player.onPlayerStateChanged.listen((s) {
        if (mounted) setState(() => _playing = s == PlayerState.playing);
      }),
    );
  }

  void _rebuild() {
    _score = cellularScore(_seed, rule: _rule, bpm: _bpm, scale: _scale);
    _dirty = true;
    _step.value = 0;
  }

  void _change(VoidCallback fn) {
    _player.stop();
    setState(() {
      fn();
      _rebuild();
    });
  }

  Future<void> _render() async {
    if (!_dirty && _path != null) return;
    final bytes = await compute(renderCellularWav, <String, Object>{
      'seed': _seed,
      'rule': _rule,
      'bpm': _bpm,
      'scale': _scale,
    });
    final directory = await getTemporaryDirectory();
    if (!mounted) return;
    final file = File(
      '${directory.path}/siir_cellular_${DateTime.now().microsecondsSinceEpoch}.wav',
    );
    await file.writeAsBytes(bytes, flush: true);
    if (!mounted) {
      await file.delete();
      return;
    }
    final old = _temporary;
    _temporary = file;
    _path = file.path;
    _wav = bytes;
    _dirty = false;
    if (old != null && await old.exists()) await old.delete();
  }

  Future<void> _play() async {
    if (_busy) return;
    if (_playing) {
      await _player.pause();
      return;
    }
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      await _render();
      if (!mounted) return;
      await _player.setReleaseMode(_loop ? ReleaseMode.loop : ReleaseMode.stop);
      if (_player.state == PlayerState.paused) {
        await _player.resume();
      } else {
        await _player.play(DeviceFileSource(_path!));
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not play: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export() async {
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      await _render();
      if (!mounted) return;
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Export cellular music',
        fileName: 'siir-rule-$_rule.wav',
        type: FileType.custom,
        allowedExtensions: ['wav'],
        bytes: _wav,
      );
      if (mounted && path != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('WAV exported')));
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Export failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _maths() => showMusicMaths(
    context,
    'Cellular automata / music',
    'Three neighboring bits decide the next cell. A tiny rule grows a whole score: newly lit cells become notes, while unlit cells leave space.',
    'q = 4sᵢ₋₁ + 2sᵢ + sᵢ₊₁\nsᵢ(t+1) = (rule >> q) & 1\nf(m) = 440 · 2^((m−69)/12)\nΔt = 30 / BPM\nx(t) = Σⱼ aⱼ(t)[sin(2πfⱼt) + ¼sin(4πfⱼt)] / 1.25',
    'Elementary binary automaton with periodic boundaries and 32 cells, evolved for 64 generations. Two neighboring columns share a scale degree; octaves rise across the grid. Only 0→1 transitions trigger notes; at most four distinct pitches sound per step, with rotating voicing. Each generation is an eighth note. Seed and settings fully determine the WAV. This is a compositional mapping, not a model of musical intelligence. Rule background: https://wolframscience.com/nks/p27--how-do-simple-programs-behave/',
  );
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _player.pause();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Column(
        children: [
          Row(
            children: [
              const BackButton(),
              const Expanded(
                child: Text('Cellular music', style: TextStyle(fontSize: 24)),
              ),
              TextButton(onPressed: _maths, child: const Text('Maths')),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                DropdownButton<int>(
                  value: _rule,
                  onChanged: _busy ? null : (v) => _change(() => _rule = v!),
                  items: [
                    for (final r in [30, 90, 110, 184])
                      DropdownMenuItem(value: r, child: Text('Rule $r')),
                  ],
                ),
                DropdownButton<String>(
                  value: _scale,
                  onChanged: _busy ? null : (v) => _change(() => _scale = v!),
                  items: [
                    for (final s in musicScales.keys)
                      DropdownMenuItem(value: s, child: Text(s)),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text(
                  '${_bpm.round()} BPM',
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
                Expanded(
                  child: Slider(
                    value: _bpm,
                    min: 50,
                    max: 180,
                    divisions: 130,
                    onChanged: _busy ? null : (v) => _change(() => _bpm = v),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Tap seed cells to compose',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
                TextButton(
                  onPressed:
                      _busy
                          ? null
                          : () => _change(() {
                            final random = Random();
                            _seed = List.generate(
                              32,
                              (_) => random.nextDouble() < .2 ? 1 : 0,
                            );
                          }),
                  child: const Text('Randomize'),
                ),
                IconButton(
                  tooltip: 'Single seed',
                  onPressed:
                      _busy
                          ? null
                          : () => _change(
                            () =>
                                _seed = List.generate(
                                  32,
                                  (i) => i == 16 ? 1 : 0,
                                ),
                          ),
                  icon: const Icon(Icons.restart_alt),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 32,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  for (int i = 0; i < _seed.length; i++)
                    Expanded(
                      child: GestureDetector(
                        onTap:
                            _busy
                                ? null
                                : () => _change(() {
                                  _seed = List.of(_seed);
                                  _seed[i] = 1 - _seed[i];
                                }),
                        child: Semantics(
                          label: 'Seed cell ${i + 1}',
                          toggled: _seed[i] == 1,
                          button: true,
                          child: Container(
                            margin: const EdgeInsets.all(1),
                            color:
                                _seed[i] == 1
                                    ? Theme.of(context).colorScheme.onSurface
                                    : Theme.of(
                                      context,
                                    ).colorScheme.surfaceContainerHighest,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: ColoredBox(
                  color: Colors.black,
                  child: ValueListenableBuilder<int>(
                    valueListenable: _step,
                    builder:
                        (_, step, _) => CustomPaint(
                          painter: _AutomatonPainter(_score, step),
                          child: const SizedBox.expand(),
                        ),
                  ),
                ),
              ),
            ),
          ),
          if (_busy) const LinearProgressIndicator(),
          if (_error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(_error, maxLines: 2),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                IconButton(
                  tooltip:
                      _playing
                          ? 'Pause generated music'
                          : 'Play generated music',
                  onPressed: _busy ? null : _play,
                  icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
                ),
                IconButton(
                  tooltip: 'Stop generated music',
                  onPressed: () {
                    _player.stop();
                    _step.value = 0;
                  },
                  icon: const Icon(Icons.stop),
                ),
                FilterChip(
                  label: const Text('Loop'),
                  selected: _loop,
                  onSelected: (v) {
                    setState(() => _loop = v);
                    _player.setReleaseMode(
                      v ? ReleaseMode.loop : ReleaseMode.stop,
                    );
                  },
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _busy ? null : _export,
                  icon: const Icon(Icons.file_download_outlined),
                  label: const Text('WAV'),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              'Rows → eighth notes · columns → scale pitches · amber → playhead',
              style: TextStyle(fontSize: 10),
            ),
          ),
        ],
      ),
    ),
  );
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final s in _subscriptions) {
      s.cancel();
    }
    _player.dispose();
    _step.dispose();
    final file = _temporary;
    if (file != null) {
      file.exists().then((exists) {
        if (exists) file.delete();
      });
    }
    super.dispose();
  }
}

class _AutomatonPainter extends CustomPainter {
  final CellularScore score;
  final int step;
  _AutomatonPainter(this.score, this.step);
  @override
  void paint(Canvas canvas, Size size) {
    final cw = size.width / score.rows.first.length,
        ch = size.height / score.rows.length;
    final paint = Paint();
    for (int y = 0; y < score.rows.length; y++) {
      for (int x = 0; x < score.rows[y].length; x++) {
        if (score.rows[y][x] == 0) continue;
        paint.color =
            y == step ? const Color(0xFFEAB45D) : const Color(0xFFDADADA);
        canvas.drawRect(
          Rect.fromLTWH(
            x * cw + .5,
            y * ch + .5,
            max(.5, cw - 1),
            max(.5, ch - 1),
          ),
          paint,
        );
      }
    }
    paint.color = const Color(0xFFEAB45D);
    paint.strokeWidth = 1.5;
    canvas.drawLine(
      Offset(0, (step + .5) * ch),
      Offset(size.width, (step + .5) * ch),
      paint,
    );
  }

  @override
  bool shouldRepaint(_AutomatonPainter old) =>
      old.score != score || old.step != step;
}
