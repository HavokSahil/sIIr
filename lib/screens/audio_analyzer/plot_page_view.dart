import 'package:flutter/material.dart';
import 'package:shirr/screens/audio_analyzer/plots/amp_plot_card.dart';
import 'package:shirr/screens/audio_analyzer/plots/const_q_tf_card.dart';
import 'package:shirr/screens/audio_analyzer/plots/fft_plot_card.dart';
import 'package:shirr/screens/audio_analyzer/plots/mfcc_chart.dart';
import 'package:shirr/screens/audio_analyzer/plots/phase_circle_card.dart';
import 'package:shirr/screens/audio_analyzer/plots/relative_loudness_card.dart';
import 'package:shirr/screens/audio_analyzer/plots/spectral_centroid.dart';
import 'package:shirr/screens/audio_analyzer/plots/spectral_flatness.dart';
import 'package:shirr/screens/audio_analyzer/plots/spectral_roll_off.dart';

class PlotPageView extends StatelessWidget {
  const PlotPageView({
    required this.repaintKey,
    required this.pcmBuffer,
    required this.isInteractive,
    required this.pageController,
    required this.isSwipeLocked,
    required this.sampleRate,
    super.key,
  });

  final bool isSwipeLocked;
  final GlobalKey repaintKey;
  final Stream<List<double>> pcmBuffer;
  final PageController pageController;
  final bool isInteractive;
  final int sampleRate;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      key: repaintKey,
      child: PageView(
        controller: pageController,
        scrollDirection: Axis.vertical,
        physics: isSwipeLocked ? const NeverScrollableScrollPhysics() : const BouncingScrollPhysics(),
        children: [
          AmpPlotCard(pcmBuffer: pcmBuffer, isInteractive: isInteractive),
          FrequencySpectrumChart(pcmBuffer: pcmBuffer, isInteractive: isInteractive, sampleRate: sampleRate,),
          PhaseCircleCard(pcmBuffer: pcmBuffer, isInteractive: isInteractive),
          DecibelLoudnessCard(isInteractive: isInteractive, pcmBuffer: pcmBuffer),
          MfccHeatMapCard(sampleRate: sampleRate, pcmBuffer: pcmBuffer,),
          SpectralCentroid(isInteractive: isInteractive, pcmBuffer: pcmBuffer, sampleRate: sampleRate),
          SpectralRollOffCard(isInteractive: isInteractive, pcmBuffer: pcmBuffer, sampleRate: sampleRate),
          SpectralFlatness(isInteractive: isInteractive, pcmBuffer: pcmBuffer, sampleRate: sampleRate),
          QTransformCard(pcmBuffer: pcmBuffer, sampleRate: sampleRate),
        ],
      ),
    );
  }
}
