import 'dart:math';
import 'dart:typed_data';

/// Bounded-grid incompressible dye simulation: semi-Lagrangian advection and
/// pressure projection, inspired by Stam's Stable Fluids (SIGGRAPH 1999).
class DyeFluid {
  final int width, height;
  late Float32List u, v, red, green, blue;
  late final Float32List _u, _v, _r, _g, _b, _pressure, _div;
  DyeFluid({this.width = 48, this.height = 72}) {
    final n = width * height;
    u = Float32List(n);
    v = Float32List(n);
    red = Float32List(n);
    green = Float32List(n);
    blue = Float32List(n);
    _u = Float32List(n);
    _v = Float32List(n);
    _r = Float32List(n);
    _g = Float32List(n);
    _b = Float32List(n);
    _pressure = Float32List(n);
    _div = Float32List(n);
  }
  DyeFluid resized(int newWidth, int newHeight) {
    final next = DyeFluid(width: newWidth, height: newHeight);
    final oldFields = [u, v, red, green, blue];
    final nextFields = [next.u, next.v, next.red, next.green, next.blue];
    for (int y = 0; y < newHeight; y++) {
      for (int x = 0; x < newWidth; x++) {
        final sx = x * (width - 1) / (newWidth - 1);
        final sy = y * (height - 1) / (newHeight - 1);
        for (int k = 0; k < oldFields.length; k++) {
          final scale =
              k == 0
                  ? newWidth / width
                  : k == 1
                  ? newHeight / height
                  : 1.0;
          nextFields[k][y * newWidth + x] =
              _sample(oldFields[k], sx, sy) * scale;
        }
      }
    }
    return next;
  }

  void clear() {
    for (final field in [u, v, red, green, blue]) {
      field.fillRange(0, field.length, 0);
    }
  }

  void splat(
    double x,
    double y,
    double dx,
    double dy,
    List<double> color, {
    double strength = 1,
    double radius = 3,
  }) {
    final cx = x.clamp(0.0, 1.0) * (width - 1),
        cy = y.clamp(0.0, 1.0) * (height - 1);
    for (
      int yy = max(1, (cy - radius * 3).floor());
      yy < min(height - 1, cy + radius * 3);
      yy++
    ) {
      for (
        int xx = max(1, (cx - radius * 3).floor());
        xx < min(width - 1, cx + radius * 3);
        xx++
      ) {
        final weight = exp(
          -((xx - cx) * (xx - cx) + (yy - cy) * (yy - cy)) / (radius * radius),
        );
        final i = yy * width + xx;
        u[i] = (u[i] + dx * weight).clamp(-width * 1.25, width * 1.25);
        v[i] = (v[i] + dy * weight).clamp(-height * 1.25, height * 1.25);
        red[i] = min(8, red[i] + color[0] * strength * weight);
        green[i] = min(8, green[i] + color[1] * strength * weight);
        blue[i] = min(8, blue[i] + color[2] * strength * weight);
      }
    }
  }

  double _sample(Float32List f, double x, double y) {
    x = x.clamp(0.0, width - 1.001);
    y = y.clamp(0.0, height - 1.001);
    final ix = x.floor(), iy = y.floor(), tx = x - ix, ty = y - iy;
    final i = iy * width + ix;
    return (f[i] * (1 - tx) + f[i + 1] * tx) * (1 - ty) +
        (f[i + width] * (1 - tx) + f[i + width + 1] * tx) * ty;
  }

  void step(double dt, {double decay = .985}) {
    dt = dt.clamp(0.0, .04);
    final drag = exp(-dt * 1.1);
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final i = y * width + x, sx = x - u[i] * dt, sy = y - v[i] * dt;
        _u[i] = _sample(u, sx, sy) * drag;
        _v[i] = _sample(v, sx, sy) * drag;
      }
    }
    u.setAll(0, _u);
    v.setAll(0, _v);
    _pressure.fillRange(0, _pressure.length, 0);
    for (int y = 1; y < height - 1; y++) {
      for (int x = 1; x < width - 1; x++) {
        final i = y * width + x;
        _div[i] = -.5 * (u[i + 1] - u[i - 1] + v[i + width] - v[i - width]);
      }
    }
    for (int iteration = 0; iteration < 12; iteration++) {
      for (int y = 1; y < height - 1; y++) {
        for (int x = 1; x < width - 1; x++) {
          final i = y * width + x;
          _pressure[i] =
              (_div[i] +
                  _pressure[i - 1] +
                  _pressure[i + 1] +
                  _pressure[i - width] +
                  _pressure[i + width]) *
              .25;
        }
      }
    }
    for (int y = 1; y < height - 1; y++) {
      for (int x = 1; x < width - 1; x++) {
        final i = y * width + x;
        u[i] -= .5 * (_pressure[i + 1] - _pressure[i - 1]);
        v[i] -= .5 * (_pressure[i + width] - _pressure[i - width]);
      }
    }
    for (int x = 0; x < width; x++) {
      v[x] = v[(height - 1) * width + x] = 0;
    }
    for (int y = 0; y < height; y++) {
      u[y * width] = u[y * width + width - 1] = 0;
    }
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final i = y * width + x, sx = x - u[i] * dt, sy = y - v[i] * dt;
        _r[i] = _sample(red, sx, sy) * decay;
        _g[i] = _sample(green, sx, sy) * decay;
        _b[i] = _sample(blue, sx, sy) * decay;
      }
    }
    red.setAll(0, _r);
    green.setAll(0, _g);
    blue.setAll(0, _b);
  }

  Uint8List velocityPixels() {
    final floats = Float32List(width * height * 4);
    for (int i = 0; i < u.length; i++) {
      floats[i * 4] = .5 + u[i] / width * .25;
      floats[i * 4 + 1] = .5 + v[i] / height * .25;
      floats[i * 4 + 3] = 1;
    }
    return floats.buffer.asUint8List();
  }

  Uint8List pixels() {
    final bytes = Uint8List(width * height * 4);
    for (int i = 0; i < red.length; i++) {
      bytes[i * 4] = (255 * (1 - exp(-red[i]))).round();
      bytes[i * 4 + 1] = (255 * (1 - exp(-green[i]))).round();
      bytes[i * 4 + 2] = (255 * (1 - exp(-blue[i]))).round();
      bytes[i * 4 + 3] = 255;
    }
    return bytes;
  }
}
