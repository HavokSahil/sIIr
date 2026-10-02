import 'package:flutter/material.dart';

void showMusicMaths(
  BuildContext context,
  String title,
  String intuition,
  String formula,
  String rigor,
) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder:
        (context) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 16),
                Text(intuition),
                const SizedBox(height: 20),
                SelectableText(
                  formula,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 14,
                    height: 1.7,
                  ),
                ),
                const SizedBox(height: 20),
                const Text('ASSUMPTIONS & VALIDITY'),
                const SizedBox(height: 8),
                Text(rigor, style: const TextStyle(height: 1.6)),
              ],
            ),
          ),
        ),
  );
}
