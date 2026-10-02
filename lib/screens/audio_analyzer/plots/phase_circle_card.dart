import 'dart:typed_data';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:fftea/fftea.dart';
import 'package:shirr/core/constants.dart';

class PhaseCircleCard extends StatefulWidget {
  final Stream<List<double>> pcmBuffer;
  final bool isInteractive;

  const PhaseCircleCard({
    required this.pcmBuffer,
    required this.isInteractive,
    super.key,
  });

  @override
  State<PhaseCircleCard> createState() => _PhaseCircleCardState();
}

class _PhaseCircleCardState extends State<PhaseCircleCard> {

  late int sampleRate;

  double maxFreq = 1e+4;

  @override
  void initState() {
    super.initState();
    /// TODO: REMOVE THIS HARDCODED PORTION
    sampleRate = 44100;
  }

  Float64x2List _computeSpectrum(List<double> samples) {
    final fft = FFT(samples.length);
    return fft.realFft(samples);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      elevation: 6,
      color: isDark ? Colors.black : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: StreamBuilder<List<double>>(
          stream: widget.pcmBuffer,
          builder: (context, snapshot) {
            final samples = snapshot.data ?? List.filled(128, 0.0);
            final spectrum = _computeSpectrum(samples);

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 8.0, left: 8),
                  child: Text(
                    "Phase, Frequency & Amplitude",
                    style: TextStyle(
                      fontFamily: Constants.fontFamilyBody,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onScaleUpdate: (details) => {
                      if (widget.isInteractive) {
                        setState(() {
                          maxFreq /= details.scale.clamp(0.95, 1.05);
                          maxFreq = maxFreq.clamp(100, 2e+4);
                        })
                      }
                    },
                    onDoubleTap: () => {
                      if (widget.isInteractive) {
                        setState(() {
                          maxFreq = sampleRate/2;
                        })
                      }
                    },
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: CustomPaint(
                        painter: PolarSpectrumPainter(
                          freqDomain: spectrum,
                          maxRadius: 130,
                          maxFreq: maxFreq,
                          isDark: isDark,
                          N: samples.length,
                          sampleRate: sampleRate
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class PolarSpectrumPainter extends CustomPainter {
  final Float64x2List freqDomain;
  final double maxRadius;
  final bool isDark;
  final double maxFreq;
  final int sampleRate;
  final int N;

  PolarSpectrumPainter({
    required this.freqDomain,
    required this.maxRadius,
    required this.isDark,
    required this.maxFreq,
    required this.sampleRate,
    required this.N,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final axisPaint = Paint()
      ..style = PaintingStyle.stroke
      ..color = (isDark ? Colors.white70 : Colors.black87).withAlpha(80)
      ..strokeWidth = 0.8;

    final dotPaint = Paint()..style = PaintingStyle.fill;
    final labelStyle = TextStyle(fontSize: 6, color: isDark ? Colors.white : Colors.black);

    final half = freqDomain.length ~/ 2;

    // Compute max magnitude
    double maxMagnitude = 0.0;
    for (int i = 1; i < half; i++) {
      final re = freqDomain[i].x;
      final im = freqDomain[i].y;
      final magnitude = sqrt(re * re + im * im);
      if (magnitude > maxMagnitude) maxMagnitude = magnitude;
    }

    // Draw concentric circles
    const int numRings = 4;
    for (int i = 1; i <= numRings; i++) {
      final r = maxRadius * i / numRings;
      canvas.drawCircle(center, r, axisPaint);
    }

    // Draw axis lines
    canvas.drawLine(Offset(center.dx - maxRadius, center.dy), Offset(center.dx + maxRadius, center.dy), axisPaint);
    canvas.drawLine(Offset(center.dx, center.dy - maxRadius), Offset(center.dx, center.dy + maxRadius), axisPaint);

    // Frequency ring labels
    for (int i = 1; i <= numRings; i++) {
      final freq = (i / numRings * maxFreq).round();
      final label = freq >= 1000 ? '${(freq / 1000).toStringAsFixed(1)}kHz' : '$freq Hz';
      final tp = TextPainter(
        text: TextSpan(text: label, style: labelStyle),
        textDirection: TextDirection.ltr,
      );
      tp.layout();
      tp.paint(canvas, Offset(center.dx + maxRadius * (i - 1) / numRings + 8, center.dy));
    }

    // Phase angle labels
    final angleLabels = {
      0.0: "0",
      pi / 2: "π/2",
      pi: "π",
      -pi / 2: "-π/2",
    };

    angleLabels.forEach((angle, label) {
      final dx = center.dx + (maxRadius + 12) * cos(angle);
      final dy = center.dy - (maxRadius + 12) * sin(angle); // Flip y-axis
      final tp = TextPainter(
        text: TextSpan(text: label, style: labelStyle),
        textDirection: TextDirection.ltr,
      );
      tp.layout();
      tp.paint(canvas, Offset(dx - tp.width / 2, dy - tp.height / 2));
    });

    // Plot spectrum
    for (int i = 1; i < half; i++) {
      final re = freqDomain[i].x;
      final im = freqDomain[i].y;

      final magnitude = sqrt(re * re + im * im);
      final phase = atan2(im, re);
      final frequency = i * sampleRate / N;

      if (frequency > maxFreq) continue;

      final freqRatio = frequency / maxFreq;
      final r = freqRatio * maxRadius;

      final x = center.dx + r * cos(phase);
      final y = center.dy - r * sin(phase); // Flip y-axis for correct orientation

      final brightness = (magnitude / maxMagnitude).clamp(0.0, 1.0);
      final alpha = (brightness * 255).toInt();

      dotPaint.color = (isDark ? Colors.white : Colors.black).withAlpha(alpha);
      canvas.drawCircle(Offset(x, y), 2.2, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
