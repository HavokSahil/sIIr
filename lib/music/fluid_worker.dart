import 'dart:async';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';
import 'fluid.dart';

class FluidFrame {
  final Uint8List pixels, velocity;
  final int width, height;
  const FluidFrame(this.pixels, this.velocity, this.width, this.height);
}

class FluidWorker {
  final _responses = ReceivePort();
  Isolate? _isolate;
  SendPort? _port;
  Completer<FluidFrame>? _pending;
  bool _closed = false;
  Future<void> start() async {
    final ready = Completer<void>();
    _responses.listen((event) {
      if (event is SendPort) {
        _port = event;
        ready.complete();
      } else {
        _pending?.complete(event as FluidFrame);
        _pending = null;
      }
    });
    _isolate = await Isolate.spawn(_entry, _responses.sendPort);
    if (_closed) {
      _isolate?.kill();
      return;
    }
    await ready.future;
  }

  Future<FluidFrame?> frame(Map<String, Object> input) async {
    if (_port == null || _pending != null || _closed) return null;
    final pending = _pending = Completer<FluidFrame>();
    _port!.send(input);
    return pending.future;
  }

  static void _entry(SendPort output) {
    final input = ReceivePort();
    output.send(input.sendPort);
    final fluid = DyeFluid(width: 64, height: 96);
    double time = 0;
    input.listen((message) {
      final m = message as Map;
      final sx = fluid.width / 48, sy = fluid.height / 72;
      if (m['clear'] == true) fluid.clear();
      final energy = m['energy'] as double, bass = m['bass'] as double;
      final treble = m['treble'] as double, gain = m['gain'] as double;
      final dt = m['dt'] as double;
      time += dt * (.16 + treble * .12);
      for (int k = 0; k < 3; k++) {
        final a = time + k * 2 * pi / 3;
        final x = .28 + k * .22 + .045 * sin(a), y = .82 + .018 * cos(a * .7);
        final hue = a * 40 + time * 14;
        final color = [
          for (int c = 0; c < 3; c++)
            .5 + .5 * sin(hue * pi / 180 + c * 2 * pi / 3),
        ];
        if (energy > .005) {
          fluid.splat(
            x,
            y,
            sin(a) * (3 + bass * 5) * gain * sx * dt,
            -(5 + bass * 12) * gain * sy * dt,
            color,
            strength:
                (energy * gain * .55 + (m['onset'] as double) * .1) * dt * 30,
            radius: (2 + bass * 3) * sx,
          );
        }
      }
      for (final raw in m['touches'] as List) {
        final t = raw as List<double>;
        fluid.splat(
          t[0],
          t[1],
          t[2] * sx * .15,
          t[3] * sy * .15,
          [.2, .65, 1],
          strength: 1.5,
          radius: 3 * sx,
        );
      }
      fluid.step(dt, decay: m['decay'] as double);
      output.send(
        FluidFrame(
          fluid.pixels(),
          fluid.velocityPixels(),
          fluid.width,
          fluid.height,
        ),
      );
    });
  }

  void dispose() {
    _closed = true;
    _isolate?.kill(priority: Isolate.immediate);
    _responses.close();
    _pending?.complete(FluidFrame(Uint8List(0), Uint8List(0), 0, 0));
    _pending = null;
  }
}
