import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shirr/core/theme.dart';
import 'package:shirr/screens/main_menu/main_menu_screen.dart';
import 'package:shirr/screens/audio_generator/audio_generator_screen.dart';
import 'package:shirr/workbench/analysis.dart';
import 'package:shirr/workbench/workbench_screen.dart';

// Regenerate real Flutter UI renders with:
// flutter test tool/render_store_screenshots.dart
// Platform audio is mocked; these captures do not verify device audio.
void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    final messenger = binding.defaultBinaryMessenger;
    for (final name in [
      'xyz.luan/audioplayers.global',
      'xyz.luan/audioplayers.global/events',
    ]) {
      messenger.setMockMethodCallHandler(
        MethodChannel(name),
        (_) async => null,
      );
    }
    messenger.setMockMethodCallHandler(
      const MethodChannel('flutter.baseflow.com/permissions/methods'),
      (call) async => 1,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('audio_streamer.methodChannel'),
      (_) async => 22050,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('audio_streamer.eventChannel'),
      (_) async => null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers'),
      (call) async {
        if (call.method == 'create') {
          final id = (call.arguments as Map)['playerId'];
          messenger.setMockMethodCallHandler(
            MethodChannel('xyz.luan/audioplayers/events/$id'),
            (_) async => null,
          );
        }
        return null;
      },
    );
  });

  testWidgets('render store screenshots', (tester) async {
    await tester.runAsync(() async {
      for (final entry
          in {
            'Gwendolyne': [
              'assets/fonts/Gwendolyn-Regular.ttf',
              'assets/fonts/Gwendolyn-Bold.ttf',
            ],
            'ElMessiri': [
              'assets/fonts/ElMessiri-Regular.ttf',
              'assets/fonts/ElMessiri-Bold.ttf',
            ],
            'Zain': [
              'assets/fonts/Zain-Regular.ttf',
              'assets/fonts/Zain-Bold.ttf',
            ],
            'Roboto': ['assets/fonts/Zain-Regular.ttf'],
            'monospace': ['assets/fonts/Zain-Regular.ttf'],
            'MaterialIcons': ['fonts/MaterialIcons-Regular.otf'],
          }.entries) {
        final loader = FontLoader(entry.key);
        for (final asset in entry.value) {
          loader.addFont(rootBundle.load(asset));
        }
        await loader.load();
      }
      final sdk =
          Platform.environment['FLUTTER_ROOT'] ??
          RegExp(r'^flutter.sdk=(.+)$', multiLine: true)
              .firstMatch(File('android/local.properties').readAsStringSync())!
              .group(1)!;
      for (final entry
          in {
            'Roboto':
                '$sdk/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
            'monospace': '/usr/share/fonts/noto/NotoSansMono-Regular.ttf',
          }.entries) {
        final loader = FontLoader(entry.key);
        loader.addFont(
          Future.value(
            ByteData.sublistView(File(entry.value).readAsBytesSync()),
          ),
        );
        await loader.load();
      }
    });
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final data = analyzeAudio({
      'samples': demoSamples().take(22050 * 3).toList(),
      'sampleRate': 22050,
    });
    final screens = <Widget>[
      const MainMenuScreen(),
      WorkbenchScreen(initialData: data, loadDemo: false),
      const AudioGeneratorScreen(),
    ];
    for (var i = 0; i < screens.length; i++) {
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.darkTheme,
            home: screens[i],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final boundary =
          key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 3);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        File(
          'fastlane/metadata/android/en-US/images/phoneScreenshots/${i + 1}.png',
        ).writeAsBytesSync(bytes!.buffer.asUint8List());
        image.dispose();
      });
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    }
  });
}
