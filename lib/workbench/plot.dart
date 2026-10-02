import 'dart:math';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

const inkBlue = Color(0xFF619CF5);
const inkAmber = Color(0xFFEAB45D);
const spectrogramPalette = [
  Color(0xFF000004),
  Color(0xFF420A68),
  Color(0xFF932667),
  Color(0xFFDD513A),
  Color(0xFFFCA50A),
  Color(0xFFFCFFA4),
];
Color spectrogramColor(double fraction) {
  final position = fraction.clamp(0.0, 1.0) * (spectrogramPalette.length - 1);
  final i = position.floor().clamp(0, spectrogramPalette.length - 2);
  return Color.lerp(
    spectrogramPalette[i],
    spectrogramPalette[i + 1],
    position - i,
  )!;
}

class ScientificPlot extends StatefulWidget {
  final List<Offset> points;
  final List<List<double>>? matrix;
  final bool scatter, signed;
  final bool bars, radar, envelope, spectrogram;
  final List<String> tickLabels;
  final String xLabel, yLabel, mode;
  final double minX, maxX;
  final double? cursor, rangeStart, rangeEnd, minY, maxY, colorMin, colorMax;
  final List<double> pins;
  final ValueChanged<double>? onInspect;
  final void Function(double, double)? onRange, onZoom, onPan2D;
  final ValueChanged<double>? onPan;
  final VoidCallback? onRangeEnd;
  final void Function(int, double)? onMovePin;
  const ScientificPlot({
    super.key,
    this.points = const [],
    this.matrix,
    this.radar = false,
    this.envelope = false,
    this.spectrogram = false,
    this.bars = false,
    this.tickLabels = const [],
    this.scatter = false,
    this.signed = false,
    required this.xLabel,
    required this.yLabel,
    this.minX = 0,
    required this.maxX,
    this.cursor,
    this.rangeStart,
    this.rangeEnd,
    this.minY,
    this.maxY,
    this.colorMin,
    this.colorMax,
    this.pins = const [],
    this.onInspect,
    this.onRange,
    this.onRangeEnd,
    this.onPan,
    this.onZoom,
    this.onPan2D,
    this.onMovePin,
    this.mode = 'Inspect',
  });
  @override
  State<ScientificPlot> createState() => _ScientificPlotState();
}

class _ScientificPlotState extends State<ScientificPlot> {
  double? _start;
  double _scale = 1;
  int? _dragPin;
  String? _readout;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final w = widget;
      final width = max(1.0, constraints.maxWidth - 72);
      double domain(Offset p) =>
          w.minX + ((p.dx - 36) / width).clamp(0.0, 1.0) * (w.maxX - w.minX);
      return Listener(
        onPointerSignal: (event) {
          if (event is PointerScrollEvent && w.onZoom != null) {
            GestureBinding.instance.pointerSignalResolver.register(event, (
              signal,
            ) {
              w.onZoom!(
                event.scrollDelta.dy > 0 ? 1.15 : 0.87,
                domain(event.localPosition),
              );
            });
          }
        },
        child: GestureDetector(
          dragStartBehavior: DragStartBehavior.down,
          onTapUp: (d) => w.onInspect?.call(domain(d.localPosition)),
          onScaleStart: (d) {
            _scale = 1;
            _start = domain(d.localFocalPoint);
            _dragPin = null;
            if (w.mode == 'Pin' && w.pins.isNotEmpty) {
              final distances = w.pins.map((p) => (p - _start!).abs()).toList();
              final nearest = distances.reduce(min);
              if (nearest / max(1e-12, w.maxX - w.minX) * width < 14) {
                _dragPin = distances.indexOf(nearest);
              }
            }
          },
          onScaleEnd: (_) {
            if (w.mode == 'Range') w.onRangeEnd?.call();
          },
          onScaleUpdate: (d) {
            final x = domain(d.localFocalPoint);
            if (d.pointerCount > 1) {
              w.onZoom?.call(_scale / d.scale, x);
              _scale = d.scale;
              return;
            }
            if (_dragPin != null) {
              w.onMovePin?.call(_dragPin!, x);
            } else if (w.mode == 'Range') {
              w.onRange?.call(min(_start ?? x, x), max(_start ?? x, x));
            } else if (w.mode == 'Pan') {
              w.onPan?.call(-d.focalPointDelta.dx / width * (w.maxX - w.minX));
              w.onPan2D?.call(
                -d.focalPointDelta.dx / width * (w.maxX - w.minX),
                d.focalPointDelta.dy /
                    max(1.0, constraints.maxHeight - 64) *
                    ((w.maxY ?? 1) - (w.minY ?? 0)),
              );
            } else if (w.mode != 'Pin') {
              w.onInspect?.call(x);
            }
          },
          child: MouseRegion(
            cursor:
                w.mode == 'Pan'
                    ? SystemMouseCursors.grab
                    : SystemMouseCursors.precise,
            onExit: (_) => setState(() => _readout = null),
            onHover: (event) {
              final x = domain(event.localPosition);
              String value = 'x ${x.toStringAsPrecision(5)}';
              if (w.points.isNotEmpty) {
                final nearest = w.points.reduce(
                  (a, b) => (a.dx - x).abs() < (b.dx - x).abs() ? a : b,
                );
                value =
                    'x ${nearest.dx.toStringAsPrecision(5)} · y ${nearest.dy.toStringAsPrecision(5)}';
              } else if (w.matrix != null &&
                  w.matrix!.isNotEmpty &&
                  w.matrix!.first.isNotEmpty) {
                final r = (((event.localPosition.dy - 32) /
                            max(1.0, constraints.maxHeight - 64)) *
                        w.matrix!.length)
                    .floor()
                    .clamp(0, w.matrix!.length - 1);
                final c = (((x - w.minX) / max(1e-12, w.maxX - w.minX)) *
                        w.matrix![r].length)
                    .floor()
                    .clamp(0, w.matrix![r].length - 1);
                value +=
                    ' · row $r · value ${w.matrix![r][c].toStringAsPrecision(5)}';
              }
              setState(() => _readout = value);
            },
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _PlotPainter(
                      w.points,
                      w.matrix,
                      w.scatter,
                      w.signed,
                      w.xLabel,
                      w.yLabel,
                      w.minX,
                      w.maxX,
                      w.cursor,
                      w.rangeStart,
                      w.rangeEnd,
                      w.pins,
                      Theme.of(context).colorScheme.onSurface,
                      w.minY,
                      w.maxY,
                      w.colorMin,
                      w.colorMax,
                      w.bars,
                      w.tickLabels,
                      w.radar,
                      w.envelope,
                      w.spectrogram,
                    ),
                  ),
                ),
                if (_readout != null)
                  Positioned(
                    right: 16,
                    top: 28,
                    child: IgnorePointer(
                      child: Container(
                        color: Theme.of(
                          context,
                        ).colorScheme.surface.withValues(alpha: 0.95),
                        padding: const EdgeInsets.all(6),
                        child: Text(
                          _readout!,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 10,
                          ),
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
  );
}

class _PlotPainter extends CustomPainter {
  final List<Offset> points;
  final List<List<double>>? matrix;
  final bool scatter, signed;
  final bool bars, radar, envelope, spectrogram;
  final List<String> tickLabels;
  final String xLabel, yLabel;
  final double minX, maxX;
  final double? cursor, start, end;
  final List<double> pins;
  final Color ink;
  final double? minY, maxY, colorMin, colorMax;
  _PlotPainter(
    this.points,
    this.matrix,
    this.scatter,
    this.signed,
    this.xLabel,
    this.yLabel,
    this.minX,
    this.maxX,
    this.cursor,
    this.start,
    this.end,
    this.pins,
    this.ink,
    this.minY,
    this.maxY,
    this.colorMin,
    this.colorMax,
    this.bars,
    this.tickLabels,
    this.radar,
    this.envelope,
    this.spectrogram,
  );
  void label(
    Canvas canvas,
    String s,
    Offset at, {
    Color? color,
    TextAlign align = TextAlign.left,
    double? maxWidth,
  }) {
    final p = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(
          fontSize: 10,
          fontFamily: 'monospace',
          color: color ?? ink.withValues(alpha: 0.82),
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth ?? double.infinity);
    final shift =
        align == TextAlign.center
            ? p.width / 2
            : align == TextAlign.right
            ? p.width
            : 0.0;
    p.paint(canvas, at - Offset(shift, 0));
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width < 70 || size.height < 70) return;
    if (radar) {
      _radar(canvas, size);
      return;
    }
    final rect = Rect.fromLTRB(36, 32, size.width - 36, size.height - 32);
    final dx = max(1e-12, maxX - minX);
    double x(double v) => rect.left + (v - minX) / dx * rect.width;
    final visible = points.where((p) => p.dx >= minX && p.dx <= maxX).toList();
    double low = 0, high = 1;
    if (visible.isNotEmpty) {
      low = visible.map((p) => p.dy).reduce(min);
      high = visible.map((p) => p.dy).reduce(max);
      if (low == high) {
        low -= 0.5;
        high += 0.5;
      }
      final pad = (high - low) * 0.08;
      low -= pad;
      high += pad;
    }
    if (minY != null && maxY != null) {
      low = minY!;
      high = maxY!;
    }
    if (envelope) {
      final extent = max(.01, max(low.abs(), high.abs()));
      low = -extent;
      high = extent;
    }
    if (bars) {
      low = min(0, low);
      high = max(0, high);
    }
    double y(double v) => rect.bottom - (v - low) / (high - low) * rect.height;
    final centralYAxis = matrix == null && !bars && !scatter;
    final valueAxisX = centralYAxis ? size.width / 2 : rect.left;
    final grid =
        Paint()
          ..color = ink.withValues(alpha: 0.1)
          ..strokeWidth = 1;
    for (int i = 0; i <= 4; i++) {
      final yy = rect.top + rect.height * i / 4;
      final xx = rect.left + rect.width * i / 4;
      canvas.drawLine(Offset(rect.left, yy), Offset(rect.right, yy), grid);
      if (i > 0 && i < 4) {
        canvas.drawLine(Offset(xx, rect.top), Offset(xx, rect.bottom), grid);
      }
      if (tickLabels.isEmpty) {
        label(
          canvas,
          (minX + dx * i / 4).toStringAsFixed(maxX < 100 ? 2 : 0),
          Offset(xx, rect.bottom + 5),
          align: TextAlign.center,
        );
      }
    }
    canvas.drawLine(
      Offset(valueAxisX, rect.top),
      Offset(valueAxisX, rect.bottom),
      Paint()
        ..color = ink.withValues(alpha: .55)
        ..strokeWidth = 1,
    );
    if (low < 0 && high > 0 && matrix == null) {
      canvas.drawLine(
        Offset(rect.left, y(0)),
        Offset(rect.right, y(0)),
        Paint()
          ..color = ink.withValues(alpha: .34)
          ..strokeWidth = 1,
      );
    }
    canvas.save();
    canvas.clipRect(rect);
    if (matrix != null && matrix!.isNotEmpty && matrix!.first.isNotEmpty) {
      final rows = matrix!;
      double lo = signed ? -1 : double.infinity,
          hi = signed ? 1 : double.negativeInfinity;
      if (!signed) {
        for (final row in rows) {
          for (final v in row) {
            lo = min(lo, v);
            hi = max(hi, v);
          }
        }
      }
      lo = colorMin ?? lo;
      hi = colorMax ?? hi;
      for (int r = 0; r < rows.length; r++) {
        for (int c = 0; c < rows[r].length; c++) {
          final value = rows[r][c];
          final fraction = ((value - lo) / max(1e-12, hi - lo)).clamp(0.0, 1.0);
          final color =
              signed
                  ? (value < 0
                      ? Color.lerp(
                        const Color(0xFF17202C),
                        inkBlue,
                        value.abs(),
                      )!
                      : Color.lerp(
                        const Color(0xFF17202C),
                        inkAmber,
                        value.abs(),
                      )!)
                  : spectrogram
                  ? spectrogramColor(fraction)
                  : Color.lerp(const Color(0xFF11151D), inkBlue, fraction)!;
          canvas.drawRect(
            Rect.fromLTWH(
              rect.left + c * rect.width / rows[r].length,
              rect.top + r * rect.height / rows.length,
              rect.width / rows[r].length + 0.5,
              rect.height / rows.length + 0.5,
            ),
            Paint()..color = color,
          );
        }
      }
    } else if (envelope && visible.length >= 4) {
      final band = Path()..moveTo(x(visible[1].dx), y(visible[1].dy));
      for (int i = 3; i < visible.length; i += 2) {
        band.lineTo(x(visible[i].dx), y(visible[i].dy));
      }
      for (int i = visible.length - 2; i >= 0; i -= 2) {
        band.lineTo(x(visible[i].dx), y(visible[i].dy));
      }
      band.close();
      canvas.drawPath(band, Paint()..color = ink.withValues(alpha: .18));
      canvas.drawPath(
        band,
        Paint()
          ..color = ink.withValues(alpha: .65)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    } else if (bars) {
      for (final p in visible) {
        canvas.drawRect(
          Rect.fromPoints(
            Offset(
              x(
                p.dx -
                    (visible.length > 1
                        ? (visible[1].dx - visible[0].dx).abs() * .42
                        : .34),
              ),
              y(p.dy),
            ),
            Offset(
              x(
                p.dx +
                    (visible.length > 1
                        ? (visible[1].dx - visible[0].dx).abs() * .42
                        : .34),
              ),
              y(0),
            ),
          ),
          Paint()..color = ink.withValues(alpha: .8),
        );
      }
    } else {
      final path = Path();
      for (int i = 0; i < visible.length; i++) {
        final p = Offset(x(visible[i].dx), y(visible[i].dy));
        if (scatter) {
          canvas.drawCircle(
            p,
            2.5,
            Paint()..color = ink.withValues(alpha: 0.8),
          );
        } else if (i == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      if (!scatter) {
        canvas.drawPath(
          path,
          Paint()
            ..color = ink
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4,
        );
      }
    }
    if (start != null && end != null) {
      canvas.drawRect(
        Rect.fromLTRB(x(start!), rect.top, x(end!), rect.bottom),
        Paint()..color = ink.withValues(alpha: 0.06),
      );
    }
    for (final pin in pins) {
      canvas.drawLine(
        Offset(x(pin), rect.top),
        Offset(x(pin), rect.bottom),
        Paint()
          ..color = ink.withValues(alpha: 0.5)
          ..strokeWidth = 1,
      );
    }
    if (cursor != null) {
      canvas.drawLine(
        Offset(x(cursor!), rect.top),
        Offset(x(cursor!), rect.bottom),
        Paint()
          ..color = ink
          ..strokeWidth = 1.5,
      );
    }
    canvas.restore();
    if (matrix == null) {
      for (int i = 0; i <= 4; i++) {
        final yy = rect.top + rect.height * i / 4;
        label(
          canvas,
          _number(high - (high - low) * i / 4),
          Offset(valueAxisX - 7, yy - 5),
          align: TextAlign.right,
          color: ink.withValues(alpha: .9),
        );
      }
    }
    for (int i = 0; i < tickLabels.length; i++) {
      label(
        canvas,
        tickLabels[i],
        Offset(x(i.toDouble()), rect.bottom + 5),
        align: TextAlign.center,
      );
    }
    label(
      canvas,
      yLabel,
      Offset(centralYAxis ? size.width / 2 : rect.left, 9),
      align: centralYAxis ? TextAlign.center : TextAlign.left,
      maxWidth: rect.width,
    );
    label(
      canvas,
      xLabel,
      Offset(size.width / 2, size.height - 13),
      align: TextAlign.center,
      maxWidth: rect.width,
    );
    if (visible.isEmpty && matrix == null) {
      label(
        canvas,
        'No measurements in this viewport',
        Offset(60, rect.center.dy),
      );
    }
  }

  String _number(double value) {
    if (value.abs() < 1e-10) return '0';
    if (value.abs() >= 1000) return '${(value / 1000).toStringAsPrecision(2)}k';
    if (value.abs() >= 10) return value.toStringAsFixed(0);
    return value.toStringAsPrecision(2);
  }

  void _radar(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) * .38;
    final count = points.length;
    if (count < 3) return;
    Offset at(int i, double value) =>
        center +
        Offset(
              cos(-pi / 2 + 2 * pi * i / count),
              sin(-pi / 2 + 2 * pi * i / count),
            ) *
            radius *
            value;
    for (int ring = 1; ring <= 4; ring++) {
      final path = Path();
      for (int i = 0; i < count; i++) {
        final p = at(i, ring / 4);
        if (i == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      path.close();
      canvas.drawPath(
        path,
        Paint()
          ..color = ink.withValues(alpha: .12)
          ..style = PaintingStyle.stroke,
      );
    }
    final scale = max(1e-12, points.map((p) => p.dy).reduce(max));
    final shape = Path();
    for (int i = 0; i < count; i++) {
      canvas.drawLine(
        center,
        at(i, 1),
        Paint()..color = ink.withValues(alpha: .12),
      );
      final title = at(i, 1.12);
      label(
        canvas,
        tickLabels.length > i ? tickLabels[i] : i.toString(),
        title - const Offset(0, 5),
        align: TextAlign.center,
      );
      final p = at(i, points[i].dy / scale);
      if (i == 0) {
        shape.moveTo(p.dx, p.dy);
      } else {
        shape.lineTo(p.dx, p.dy);
      }
      canvas.drawCircle(p, 2.5, Paint()..color = ink);
    }
    shape.close();
    canvas.drawPath(shape, Paint()..color = ink.withValues(alpha: .16));
    canvas.drawPath(
      shape,
      Paint()
        ..color = ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );
  }

  @override
  bool shouldRepaint(covariant _PlotPainter oldDelegate) => true;
}
