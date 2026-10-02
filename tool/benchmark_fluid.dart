import 'dart:io';
import 'package:shirr/music/fluid.dart';

void main() {
  for (final width in [48, 64, 128, 192, 256]) {
    final fluid = DyeFluid(width: width, height: width * 3 ~/ 2);
    final timer = Stopwatch()..start();
    for (int i = 0; i < 120; i++) {
      fluid.splat(.5, .5, width / 2, -width / 2, [
        1,
        .3,
        .6,
      ], radius: width / 16);
      fluid.step(1 / 30);
      fluid.pixels();
    }
    timer.stop();
    stdout.writeln(
      '$width columns: ${(timer.elapsedMicroseconds / 120 / 1000).toStringAsFixed(2)} ms/step (host, not device FPS)',
    );
  }
}
