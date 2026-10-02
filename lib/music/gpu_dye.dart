import 'dart:ui' as ui;

/// GPU-resident dye feedback. The pressure-projected velocity field is supplied
/// by the small worker grid; dye advection runs at the selected display quality.
class GpuDye {
  final ui.FragmentProgram program, displayProgram;
  ui.Image? _dye;
  double _time = 0;
  GpuDye(this.program, this.displayProgram);
  static Future<GpuDye> load() async {
    final programs = await Future.wait([
      ui.FragmentProgram.fromAsset('shaders/fluid_dye.frag'),
      ui.FragmentProgram.fromAsset('shaders/fluid_display.frag'),
    ]);
    return GpuDye(programs[0], programs[1]);
  }

  void display(
    ui.Canvas canvas,
    ui.Size size,
    ui.Image dye, {
    double exposure = 4,
  }) {
    final shader = displayProgram.fragmentShader();
    shader.setFloat(0, size.width);
    shader.setFloat(1, size.height);
    shader.setFloat(2, exposure);

    shader.setImageSampler(0, dye, filterQuality: ui.FilterQuality.low);
    canvas.drawRect(ui.Offset.zero & size, ui.Paint()..shader = shader);
    shader.dispose();
  }

  ui.Image render(
    ui.Image velocity, {
    required int width,
    required int height,
    required double energy,
    required double bass,
    required double treble,
    required double gain,
    required double onset,
    required double decay,
    required List<List<double>> touches,
    bool clear = false,
    double dt = 1 / 30,
  }) {
    if (_dye == null || clear) {
      _dye?.dispose();
      final recorder = ui.PictureRecorder();
      ui.Canvas(
        recorder,
      ).drawColor(const ui.Color(0xFF000000), ui.BlendMode.src);
      final picture = recorder.endRecording();
      _dye = picture.toImageSync(
        width,
        height,
        targetFormat: ui.TargetPixelFormat.rgbaFloat32,
      );
      picture.dispose();
    }
    _time += dt * (.16 + treble * .12);
    final shader = program.fragmentShader();
    final values = [
      width.toDouble(),
      height.toDouble(),
      dt,
      decay,
      _time,
      energy,
      bass,
      treble,
      gain,
      onset,
    ];
    for (int i = 0; i < 4; i++) {
      if (i < touches.length) {
        values.addAll([touches[i][0], touches[i][1], 1.0, 1.0]);
      } else {
        values.addAll([0, 0, 0, 0]);
      }
    }
    for (int i = 0; i < values.length; i++) {
      shader.setFloat(i, values[i]);
    }
    shader.setImageSampler(0, _dye!, filterQuality: ui.FilterQuality.low);
    shader.setImageSampler(1, velocity, filterQuality: ui.FilterQuality.low);
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawRect(
      ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      ui.Paint()..shader = shader,
    );
    final picture = recorder.endRecording();
    final next = picture.toImageSync(
      width,
      height,
      targetFormat: ui.TargetPixelFormat.rgbaFloat32,
    );
    picture.dispose();
    shader.dispose();
    _dye!.dispose();
    _dye = next;
    // The view owns its clone; the simulation retains its own feedback handle.
    return next.clone();
  }

  void dispose() {
    _dye?.dispose();
    _dye = null;
  }
}
