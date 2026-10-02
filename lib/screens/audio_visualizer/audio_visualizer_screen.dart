import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';
import '../../music/fluid_worker.dart';
import '../../music/gpu_dye.dart';
import '../../music/music_audio.dart';
import '../../music/maths_sheet.dart';

class AudioVisualizerScreen extends StatefulWidget {
  const AudioVisualizerScreen({super.key});
  @override
  State<AudioVisualizerScreen> createState() => _AudioVisualizerScreenState();
}

class _AudioVisualizerScreenState extends State<AudioVisualizerScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final _audio = MusicAudio();
  final _fluid = FluidWorker();
  final _touches = <List<double>>[];
  final _image = ValueNotifier<ui.Image?>(null);
  late final Ticker _ticker;
  Duration? _lastTick;
  double _energy = 0, _bass = 0, _treble = 0, _onset = 0;
  bool _rendering = false, _clear = false, _fullscreen = false, _active = true;
  double _gain = 1.2, _decay = .985, _aspect = 1.5;
  double _exposure = 4;
  int _resolution = 512;
  GpuDye? _gpu;
  final _profileFrames = <ui.FrameTiming>[];
  final _profileClock = Stopwatch();
  int _renderedFrames = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ticker = createTicker(_tick);
    if (kProfileMode) {
      _profileClock.start();
      WidgetsBinding.instance.addTimingsCallback(_timings);
    }
    _startFluid();
  }

  Future<void> _startFluid() async {
    try {
      final gpu = await GpuDye.load();
      if (!mounted) {
        gpu.dispose();
        return;
      }
      _gpu = gpu;
    } catch (_) {
      /* CPU dye remains available if custom shaders are unsupported. */
    }
    await _fluid.start();
    if (mounted) _ticker.start();
  }

  void _tick(Duration elapsed) {
    if (_rendering || !_active) return;
    final dt =
        _lastTick == null
            ? 1 / 60
            : (elapsed - _lastTick!).inMicroseconds / 1e6;
    _lastTick = elapsed;
    _frame(dt.clamp(1 / 120, .04));
  }

  Future<void> _frame(double dt) async {
    if (_rendering || !_active) return;
    _rendering = true;
    try {
      _energy += (_audio.energy - _energy) * (1 - exp(-dt * 8));
      _bass += (_audio.bass - _bass) * (1 - exp(-dt * 6));
      _treble += (_audio.treble - _treble) * (1 - exp(-dt * 5));
      _onset += (_audio.onset - _onset) * (1 - exp(-dt * 10));
      final fade = pow(_decay, dt * 30).toDouble();
      final touches = List<List<double>>.of(_touches);
      final clear = _clear;
      _touches.clear();
      _clear = false;
      final frame = await _fluid.frame({
        'width': _resolution,
        'height': (_resolution * _aspect).round().clamp(
          _resolution,
          _resolution * 3,
        ),
        'dt': dt,
        'energy': _energy,
        'bass': _bass,
        'treble': _treble,
        'onset': _onset,
        'gain': _gain,
        'decay': fade,
        'clear': clear,
        'touches': touches,
      });
      if (!mounted || frame == null || frame.pixels.isEmpty) return;
      final ready = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        _gpu == null ? frame.pixels : frame.velocity,
        frame.width,
        frame.height,
        _gpu == null ? ui.PixelFormat.rgba8888 : ui.PixelFormat.rgbaFloat32,
        ready.complete,
      );
      final decoded = await ready.future;
      if (!mounted) {
        decoded.dispose();
        return;
      }
      final next =
          _gpu?.render(
            decoded,
            width: _resolution,
            height: (_resolution * _aspect).round().clamp(
              _resolution,
              _resolution * 3,
            ),
            dt: dt,
            energy: _energy,
            bass: _bass,
            treble: _treble,
            gain: _gain,
            onset: _onset,
            decay: fade,
            touches: touches,
            clear: clear,
          ) ??
          decoded;
      if (_gpu != null) decoded.dispose();
      if (!mounted) {
        next.dispose();
        return;
      }
      final old = _image.value;
      _image.value = next;
      _renderedFrames++;
      if (old != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
      }
    } finally {
      _rendering = false;
    }
  }

  void _timings(List<ui.FrameTiming> timings) {
    _profileFrames.addAll(timings);
    if (_profileFrames.length < 120) return;
    final raster =
        _profileFrames
            .map((f) => f.rasterDuration.inMicroseconds / 1000)
            .toList()
          ..sort();
    final build =
        _profileFrames
            .map((f) => f.buildDuration.inMicroseconds / 1000)
            .toList()
          ..sort();
    final index = (raster.length * .95).floor().clamp(0, raster.length - 1);
    final fps =
        _renderedFrames * 1000 / max(1, _profileClock.elapsedMilliseconds);
    debugPrint(
      'Fluid profile: ${fps.toStringAsFixed(1)} updates/s; build p95 ${build[index].toStringAsFixed(2)} ms; raster p95 ${raster[index].toStringAsFixed(2)} ms',
    );
    _profileFrames.clear();
    _renderedFrames = 0;
    _profileClock.reset();
  }

  void _fullscreenMode(bool value) {
    setState(() => _fullscreen = value);
    SystemChrome.setEnabledSystemUIMode(
      value ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
    _lastTick = null;
    if (!_active) {
      _audio.player.pause();
      if (_audio.live) _audio.microphone();
    }
  }

  void _maths() => showMusicMaths(
    context,
    'Fluid / music coupling',
    'Sound pours colored dye into a moving flow. Bass pushes broad currents; treble stirs faster ribbons. Drag a finger to inject your own vortex.',
    '∂u/∂t + (u·∇)u = −∇p + f;  ∇·u = 0\n∂d/∂t + u·∇d = −λd + s\nu ← u − ∇p;  ∇²p = ∇·u\ndₜ₊Δt(x) ≈ dₜ(x − Δt·u(x))\nE = clamp(g·RMS, 0, 1)',
    'Semi-Lagrangian advection and a 12-iteration pressure projection on an adjustable grid (384–768 dye columns, height matched to the view; velocity uses a 64 × 96 worker grid), inspired by Jos Stam, Stable Fluids (SIGGRAPH 1999). Dye is a visual tracer; this is an artistic incompressible-flow approximation, not a water-surface model. RMS drives injection, low/high-band energy drives force, and positive energy changes accent transients. Audio controls are eased over 100–200 ms. Emitters sprout upward with continuous phase and gentle forces. Brightness affects presentation only. No beat or genre classification is implied. https://www.josstam.com/publications',
  );
  void _settings() => showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder:
        (context) => StatefulBuilder(
          builder:
              (context, update) => Padding(
                padding: const EdgeInsets.all(24),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('FLUID CONTROLS'),
                      DropdownButton<int>(
                        value: _resolution,
                        isExpanded: true,
                        items: const [
                          DropdownMenuItem(
                            value: 384,
                            child: Text('Balanced · 384 columns'),
                          ),
                          DropdownMenuItem(
                            value: 512,
                            child: Text('High · 512 columns'),
                          ),
                          DropdownMenuItem(
                            value: 768,
                            child: Text('Ultra · 768 columns'),
                          ),
                        ],
                        onChanged: (v) => update(() => _resolution = v!),
                      ),
                      Text('Brightness ×${_exposure.toStringAsFixed(1)}'),
                      Slider(
                        value: _exposure,
                        min: 1,
                        max: 8,
                        onChanged: (v) {
                          update(() => _exposure = v);
                          setState(() {});
                        },
                      ),
                      Text('Sensitivity ×${_gain.toStringAsFixed(1)}'),
                      Slider(
                        value: _gain,
                        min: .2,
                        max: 3,
                        onChanged: (v) => update(() => _gain = v),
                      ),
                      Text('Persistence ${_decay.toStringAsFixed(3)}'),
                      Slider(
                        value: _decay,
                        min: .94,
                        max: .997,
                        onChanged: (v) => update(() => _decay = v),
                      ),
                      TextButton(
                        onPressed: () {
                          _clear = true;
                          Navigator.pop(context);
                        },
                        child: const Text('Clear dye'),
                      ),
                    ],
                  ),
                ),
              ),
        ),
  );
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_fullscreen,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _fullscreenMode(false);
    },
    child: Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Row(
              children: [
                if (!_fullscreen) const BackButton(),
                const Expanded(
                  child: Text('Fluid', style: TextStyle(fontSize: 24)),
                ),
                TextButton(onPressed: _maths, child: const Text('Maths')),
                IconButton(
                  tooltip: 'Fluid settings',
                  onPressed: _settings,
                  icon: const Icon(Icons.tune),
                ),
                IconButton(
                  tooltip: _fullscreen ? 'Exit fullscreen' : 'Fullscreen fluid',
                  onPressed: () => _fullscreenMode(!_fullscreen),
                  icon: Icon(
                    _fullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                  ),
                ),
              ],
            ),
            if (!_fullscreen)
              ListenableBuilder(
                listenable: _audio,
                builder:
                    (context, _) => Column(
                      children: [
                        Wrap(
                          alignment: WrapAlignment.center,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            TextButton.icon(
                              style: TextButton.styleFrom(
                                textStyle: const TextStyle(fontSize: 14),
                              ),
                              onPressed: _audio.busy ? null : _audio.microphone,
                              icon: Icon(
                                _audio.live ? Icons.stop : Icons.mic_none,
                              ),
                              label: Text(
                                _audio.live ? 'Stop mic' : 'Microphone',
                              ),
                            ),
                            TextButton.icon(
                              style: TextButton.styleFrom(
                                textStyle: const TextStyle(fontSize: 14),
                              ),
                              onPressed: _audio.busy ? null : _audio.import,
                              icon: const Icon(Icons.audio_file_outlined),
                              label: const Text('Audio file'),
                            ),
                            IconButton(
                              tooltip:
                                  _audio.playing ? 'Pause music' : 'Play music',
                              onPressed:
                                  _audio.path == null || _audio.busy
                                      ? null
                                      : _audio.toggle,
                              icon: Icon(
                                _audio.playing ? Icons.pause : Icons.play_arrow,
                              ),
                            ),
                          ],
                        ),
                        if (_audio.busy) const LinearProgressIndicator(),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            _audio.error.isNotEmpty
                                ? _audio.error
                                : _audio.live
                                ? 'LIVE · microphone'
                                : _audio.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        if (_audio.data != null && !_audio.live)
                          Slider(
                            value: _audio.position.clamp(
                              0.0,
                              _audio.data!.duration,
                            ),
                            max: max(.01, _audio.data!.duration),
                            onChanged: _audio.busy ? null : _audio.previewSeek,
                            onChangeEnd: _audio.busy ? null : _audio.seek,
                          ),
                      ],
                    ),
              ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: LayoutBuilder(
                    builder: (context, size) {
                      _aspect = size.maxHeight / size.maxWidth;
                      return GestureDetector(
                        onPanDown:
                            (d) => _touches.add([
                              d.localPosition.dx / size.maxWidth,
                              d.localPosition.dy / size.maxHeight,
                              0,
                              -20,
                            ]),
                        onPanUpdate: (d) {
                          if (_touches.length < 16) {
                            _touches.add([
                              d.localPosition.dx / size.maxWidth,
                              d.localPosition.dy / size.maxHeight,
                              d.delta.dx * 4,
                              d.delta.dy * 4,
                            ]);
                          }
                        },
                        child: ColoredBox(
                          color: Colors.black,
                          child: ValueListenableBuilder<ui.Image?>(
                            valueListenable: _image,
                            builder:
                                (_, image, _) => Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    if (image != null)
                                      _gpu != null
                                          ? CustomPaint(
                                            painter: _DyePainter(
                                              _gpu!,
                                              image,
                                              _exposure,
                                            ),
                                          )
                                          : RawImage(
                                            image: image,
                                            fit: BoxFit.fill,
                                            filterQuality: FilterQuality.high,
                                          ),
                                    if (!_audio.live && !_audio.playing)
                                      const Center(
                                        child: IgnorePointer(
                                          child: Text(
                                            'Play music or drag to stir',
                                            style: TextStyle(
                                              color: Colors.white54,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
            if (!_fullscreen)
              const Padding(
                padding: EdgeInsets.all(8),
                child: Text(
                  'Bass → currents · treble → ribbons · touch → dye',
                  style: TextStyle(fontSize: 11),
                ),
              ),
          ],
        ),
      ),
    ),
  );
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    if (kProfileMode) WidgetsBinding.instance.removeTimingsCallback(_timings);
    _fluid.dispose();
    _gpu?.dispose();
    _audio.dispose();
    _image.value?.dispose();
    _image.dispose();
    if (_fullscreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    super.dispose();
  }
}

class _DyePainter extends CustomPainter {
  final GpuDye gpu;
  final ui.Image image;
  final double exposure;
  _DyePainter(this.gpu, this.image, this.exposure);
  @override
  void paint(Canvas canvas, Size size) =>
      gpu.display(canvas, size, image, exposure: exposure);
  @override
  bool shouldRepaint(_DyePainter old) =>
      old.image != image || old.exposure != exposure;
}
