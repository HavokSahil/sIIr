import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../core/constants.dart';
import '../screens/audio_analyzer/theme_colors.dart';

/// The original layered discs, used as navigation and instrument controls.
class ShirrDisc extends StatelessWidget {
  final String asset, tooltip;
  final VoidCallback? onPressed;
  final double size;
  final bool selected;
  const ShirrDisc({
    super.key,
    required this.asset,
    required this.tooltip,
    this.onPressed,
    this.size = 48,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: Opacity(
          opacity: onPressed == null ? 0.4 : 1,
          child: SizedBox(
            width: size,
            height: size,
            child: Material(
              color: Colors.transparent,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onPressed,
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow:
                        selected
                            ? [
                              BoxShadow(
                                color: ThemeColors.of(
                                  context,
                                ).textColor.withValues(alpha: 0.35),
                                blurRadius: 14,
                                spreadRadius: 1,
                              ),
                            ]
                            : [],
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SvgPicture.asset(
                        dark
                            ? Constants.pathCircleDarkBottom
                            : Constants.pathCircleLightBottom,
                        width: size,
                        height: size,
                      ),
                      SvgPicture.asset(
                        dark
                            ? Constants.pathCircleDarkMid
                            : Constants.pathCircleLightMid,
                        width: size * .8,
                        height: size * .8,
                      ),
                      SvgPicture.asset(
                        dark
                            ? Constants.pathCircleDarkTop
                            : Constants.pathCircleLightTop,
                        width: size * .66,
                        height: size * .66,
                      ),
                      SvgPicture.asset(
                        asset,
                        width:
                            asset.contains('play_button_') ? size : size * .65,
                        height:
                            asset.contains('play_button_') ? size : size * .65,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The asymmetric rounded branches from Shirr's original analyzer.
class ShirrBranch extends StatelessWidget {
  final List<Widget> children;
  final bool fromLeft;
  const ShirrBranch({super.key, required this.children, this.fromLeft = false});
  @override
  Widget build(BuildContext context) {
    final colors = ThemeColors.of(context);
    return Container(
      height: 68,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: colors.panelPrimary,
        borderRadius:
            fromLeft
                ? const BorderRadius.horizontal(right: Radius.circular(42))
                : const BorderRadius.horizontal(left: Radius.circular(42)),
        border: Border.all(color: colors.panelSecondary, width: 5),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: children,
      ),
    );
  }
}

class ShirrPlotFrame extends StatelessWidget {
  final Widget child;
  const ShirrPlotFrame({super.key, required this.child});
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF080808) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: (dark ? Colors.white : Colors.black).withValues(alpha: .18),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? .18 : .05),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(borderRadius: BorderRadius.circular(15), child: child),
    );
  }
}
