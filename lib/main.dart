import 'package:flutter/material.dart';
import 'package:shirr/screens/main_menu/main_menu_screen.dart';
import 'package:shirr/screens/audio_generator/audio_generator_screen.dart';
import 'package:shirr/screens/audio_visualizer/audio_visualizer_screen.dart';
import './core/constants.dart';
import './core/theme.dart';
import 'workbench/workbench_screen.dart';

void main() {
  return runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: Constants.appName,
      darkTheme: AppTheme.darkTheme,
      theme: AppTheme.lightTheme,
      themeMode: ThemeMode.system,
      initialRoute: Constants.routeMainMenu,
      debugShowCheckedModeBanner: false,
      routes: {
        Constants.routeMainMenu: (context) => MainMenuScreen(),
        Constants.routeAudioAnalyzer: (context) => const WorkbenchScreen(),
        Constants.routeAudioGenerator: (context) => AudioGeneratorScreen(),
        Constants.routeAudioVisualizer: (context) => AudioVisualizerScreen(),
      },
    );
  }
}
