import 'dart:async';
import 'package:shirr/main.dart';
import 'package:shirr/screens/main_menu/main_menu_screen.dart';
import 'package:shirr/music/fluid.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shirr/core/theme.dart';
import 'package:shirr/workbench/analysis.dart';
import 'package:shirr/workbench/tools.dart';
import 'package:shirr/workbench/plot.dart';
import 'package:shirr/workbench/workbench_screen.dart';
import 'package:shirr/screens/audio_generator/audio_generator_screen.dart';
import 'package:shirr/screens/audio_visualizer/audio_visualizer_screen.dart';
import 'dart:ui' as ui;
import 'package:shirr/music/gpu_dye.dart';

void main() {
  testWidgets('sIIr opens directly to its menu without an intro delay', (
    tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await tester.pump();
    expect(find.byType(MainMenuScreen), findsOneWidget);
    expect(find.bySemanticsLabel('sIIr'), findsOneWidget);
  });
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

  testWidgets(
    'GPU dye renders at high resolution and preserves feedback on resize',
    (tester) async {
      await tester.runAsync(() async {
        final gpu = await GpuDye.load();
        final ready = Completer<ui.Image>();
        ui.decodeImageFromPixels(
          DyeFluid(width: 64, height: 96).velocityPixels(),
          64,
          96,
          ui.PixelFormat.rgbaFloat32,
          ready.complete,
        );
        final velocity = await ready.future;
        final first = gpu.render(
          velocity,
          width: 512,
          height: 768,
          energy: 0,
          bass: 0,
          treble: 0,
          gain: 1,
          onset: 0,
          decay: .99,
          touches: [
            [.5, .5, 0, 0],
          ],
        );
        expect(first.width, 512);
        final firstBytes = await first.toByteData();
        expect(
          firstBytes!.getUint8((384 * 512 + 256) * 4 + 2),
          greaterThan(100),
        );
        first.dispose();
        final next = gpu.render(
          velocity,
          width: 768,
          height: 1152,
          energy: 0,
          bass: 0,
          treble: 0,
          gain: 1,
          onset: 0,
          decay: .99,
          touches: [],
        );
        final bytes = await next.toByteData();
        expect(next.width, 768);
        expect(bytes!.getUint8((576 * 768 + 384) * 4 + 2), greaterThan(100));
        final displayRecorder = ui.PictureRecorder();
        gpu.display(ui.Canvas(displayRecorder), const Size(768, 1152), next);
        final displayPicture = displayRecorder.endRecording();
        final display = displayPicture.toImageSync(768, 1152);
        displayPicture.dispose();
        final lit = await display.toByteData();
        final edge = (576 * 768 + 396) * 4 + 2;
        expect(lit!.getUint8(edge), greaterThan(bytes.getUint8(edge)));
        display.dispose();
        next.dispose();
        velocity.dispose();
        gpu.dispose();
      });
    },
  );

  testWidgets('details playback slider updates while the sheet stays open', (
    tester,
  ) async {
    await load(tester, const Size(390, 844));
    await tester.tap(find.byTooltip('Analysis details'));
    await tester.pumpAndSettle();
    final slider = find.byKey(const ValueKey('details-playback'));
    await tester.drag(slider, const Offset(70, 0));
    await tester.pumpAndSettle();
    expect(tester.widget<Slider>(slider).value, greaterThan(.1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  test('both Material themes use grayscale sheet and selection colors', () {
    for (final theme in [AppTheme.darkTheme, AppTheme.lightTheme]) {
      for (final color in [
        theme.bottomSheetTheme.backgroundColor!,
        theme.bottomSheetTheme.modalBackgroundColor!,
        theme.listTileTheme.selectedTileColor!,
        theme.colorScheme.primaryContainer,
        theme.colorScheme.secondaryContainer,
        theme.colorScheme.surfaceContainerHighest,
      ]) {
        expect(color.r, color.g);
        expect(color.g, color.b);
      }
      expect(theme.bottomSheetTheme.surfaceTintColor, Colors.transparent);
    }
  });

  testWidgets('desktop tree selects tools and opens rigorous Maths sheet', (
    tester,
  ) async {
    await load(tester, const Size(1440, 900));
    expect(find.text('ANALYSIS TREE'), findsOneWidget);
    expect(find.text('FRAME INSPECTOR'), findsNothing);
    await tester.tap(find.text('Spectral centroid'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Maths'));
    await tester.pumpAndSettle();
    expect(find.text('ASSUMPTIONS & VALIDITY'), findsOneWidget);
    expect(find.textContaining('balancing the spectrum'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
  testWidgets('new music views fit a narrow phone and expose their maths', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final screen in [
      const AudioGeneratorScreen(),
      const AudioVisualizerScreen(),
    ]) {
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.darkTheme, home: screen),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        tester.takeException(),
        isNull,
        reason: screen.runtimeType.toString(),
      );
      await tester.tap(find.text('Maths'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('ASSUMPTIONS & VALIDITY'), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (screen is AudioVisualizerScreen) {
        tester.state<NavigatorState>(find.byType(Navigator)).pop();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(find.byTooltip('Fluid settings'));
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('Brightness ×4.0'), findsOneWidget);
        tester.widget<Slider>(find.byType(Slider).first).onChanged!(6);
        await tester.pump();
        expect(find.text('Brightness ×6.0'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
    }
  });
  testWidgets('phone layout provides section navigation without overflow', (
    tester,
  ) async {
    await load(tester, const Size(390, 844));
    expect(find.text('Section'), findsOneWidget);
    expect(find.text('Tool'), findsOneWidget);
    expect(find.text('Maths'), findsOneWidget);
    expect(find.text('ANALYSIS TREE'), findsNothing);
    expect(find.byType(AppBar), findsNothing);
    expect(find.text('Shirr'), findsNothing);
    expect(find.byTooltip('Choose analysis tool'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
  testWidgets('all tools render on a narrow phone and expose Maths', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final tool in tools) {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: WorkbenchScreen(
            key: ValueKey(tool.id),
            initialData: data,
            loadDemo: false,
            initialToolId: tool.id,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Maths'), findsOneWidget, reason: tool.id);
      expect(tester.takeException(), isNull, reason: tool.id);
    }
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
  testWidgets('fullscreen expands graph and preserves interactive inspection', (
    tester,
  ) async {
    await load(tester, const Size(390, 844));
    final before = tester.getSize(find.byType(ScientificPlot)).height;
    await tester.tap(find.byTooltip('Fullscreen graph'));
    await tester.pumpAndSettle();
    expect(find.text('Microphone'), findsNothing);
    expect(
      tester.getSize(find.byType(ScientificPlot)).height,
      greaterThan(before + 100),
    );
    expect(find.text('Maths'), findsOneWidget);
    await tester.tap(find.byTooltip('Exit fullscreen'));
    await tester.pumpAndSettle();
    expect(find.text('Microphone'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
  testWidgets('spectrogram has a labeled color legend and chroma uses radar', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: WorkbenchScreen(
          initialData: data,
          loadDemo: false,
          initialToolId: 'spectrogram',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('−100 dB'), findsOneWidget);
    expect(find.text('+40 dB'), findsOneWidget);
    expect(
      tester.widget<ScientificPlot>(find.byType(ScientificPlot)).spectrogram,
      isTrue,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: WorkbenchScreen(
          key: const ValueKey('radar'),
          initialData: data,
          loadDemo: false,
          initialToolId: 'chroma',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<ScientificPlot>(find.byType(ScientificPlot)).radar,
      isTrue,
    );
    expect(find.byTooltip('Zoom in'), findsNothing);
    expect(find.byTooltip('Zoom out'), findsNothing);
    expect(find.text('Pan'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
  testWidgets('file graph follows a cursor in a one-second window', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final recording = analyzeAudio({
      'samples': demoSamples().take(22050 * 10).toList(),
      'sampleRate': 22050,
      'hop': 2048,
      'lightweight': true,
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: WorkbenchScreen(initialData: recording, loadDemo: false),
      ),
    );
    await tester.pumpAndSettle();
    var plot = tester.widget<ScientificPlot>(find.byType(ScientificPlot));
    expect(plot.maxX - plot.minX, closeTo(1, 1e-9));
    final seek = tester.widget<Slider>(find.byType(Slider));
    seek.onChanged!(7);
    seek.onChangeEnd!(7);
    await tester.pump();
    plot = tester.widget<ScientificPlot>(find.byType(ScientificPlot));
    expect(plot.minX, greaterThan(4));
    expect(plot.cursor, 7);
    expect(plot.maxX - plot.minX, closeTo(1, 1e-9));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
  testWidgets('two-finger graph gesture zooms around its focal point', (
    tester,
  ) async {
    double factor = 1;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 400,
            child: ScientificPlot(
              maxX: 10,
              xLabel: 'seconds',
              yLabel: 'amplitude',
              onZoom: (f, a) => factor *= f,
            ),
          ),
        ),
      ),
    );
    final a = await tester.startGesture(const Offset(180, 180), pointer: 1);
    final b = await tester.startGesture(const Offset(240, 180), pointer: 2);
    await tester.pump();
    await a.moveTo(const Offset(130, 180));
    await b.moveTo(const Offset(290, 180));
    await tester.pump();
    expect(factor, lessThan(1));
    await a.up();
    await b.up();
    expect(tester.takeException(), isNull);
  });
  testWidgets('plot range keeps its drag anchor across parent rebuilds', (
    tester,
  ) async {
    double start = -1, end = -1;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder:
                (context, update) => SizedBox(
                  width: 400,
                  height: 300,
                  child: ScientificPlot(
                    maxX: 10,
                    xLabel: 'seconds',
                    yLabel: 'amplitude',
                    mode: 'Range',
                    rangeStart: start < 0 ? null : start,
                    rangeEnd: end < 0 ? null : end,
                    onRange:
                        (a, b) => update(() {
                          start = a;
                          end = b;
                        }),
                  ),
                ),
          ),
        ),
      ),
    );
    final gesture = await tester.startGesture(const Offset(100, 100));
    await gesture.moveTo(const Offset(180, 100));
    await tester.pump();
    await gesture.moveTo(const Offset(210, 100));
    await tester.pump();
    final anchor = start;
    expect(anchor, greaterThanOrEqualTo(0));
    await gesture.moveTo(const Offset(250, 100));
    await tester.pump();
    expect(start, anchor);
    expect(end, greaterThan(start));
    await gesture.up();
    expect(tester.takeException(), isNull);
  });
}
