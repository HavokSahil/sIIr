import 'package:shirr/workbench/shirr_chrome.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shirr/core/theme.dart';
import 'package:shirr/workbench/analysis.dart';
import 'package:shirr/workbench/workbench_screen.dart';

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
      (_) async =>
          throw PlatformException(
            code: 'recorder_not_started',
            message: 'Actual sample rate is available after capture starts.',
          ),
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
  final data = analyzeAudio({
    'samples': demoSamples().take(22050).toList(),
    'sampleRate': 22050,
  });
  Future<void> load(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: WorkbenchScreen(initialData: data, loadDemo: false),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('source selector switches to live mic and restores file stats', (
    tester,
  ) async {
    await load(tester, const Size(390, 844));
    expect(find.text('Microphone'), findsOneWidget);
    expect(find.text('Windowed stats'), findsOneWidget);
    expect(find.text('Test recording'), findsOneWidget);
    expect(find.byType(ShirrBranch), findsNothing);
    expect(find.byType(ShirrDisc), findsNWidgets(2));
    await tester.tap(find.text('Microphone'));
    for (int i = 0; i < 100 && find.text('LIVE').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(find.text('LIVE'), findsOneWidget);
    for (int i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(find.text('Test recording'), findsNothing);
    // EventChannel cancellation crosses the platform boundary outside the
    // widget test's fake clock. Let that future settle before asserting.
    await tester.runAsync(() async {
      await tester.tap(find.text('Audio file'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    for (int i = 0; i < 100 && find.text('WINDOWED').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(find.text('WINDOWED'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('Test recording'), findsOneWidget);
    expect(find.text('WINDOWED'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
