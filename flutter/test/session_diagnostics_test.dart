import 'package:flutter/material.dart';
import 'package:flutter_hbb/common/widgets/overlay.dart';
import 'package:flutter_hbb/desktop/widgets/session_diagnostics.dart';
import 'package:flutter_hbb/generated_bridge.dart';
import 'package:flutter_hbb/models/model.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

class _Binding extends Fake implements RustdeskImpl {
  @override
  String translate({
    required String name,
    required String locale,
    dynamic hint,
  }) =>
      name;

  @override
  Future<bool?> sessionGetToggleOption({
    required UuidValue sessionId,
    required String arg,
    dynamic hint,
  }) async =>
      true;
}

class _Session extends Fake implements FFI {
  @override
  final sessionId = UuidValue('00000000-0000-0000-0000-000000000000');

  @override
  late final ffiModel = FfiModel(WeakReference(this));

  @override
  late final qualityMonitorModel = QualityMonitorModel(WeakReference(this));
}

void main() {
  setUp(() => platformFFI.setBindingForTesting(_Binding()));

  testWidgets(
      'desktop quality monitor is centered on the right and passes taps',
      (tester) async {
    final session = _Session();
    await session.qualityMonitorModel
        .checkShowQualityMonitor(session.sessionId);
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => taps++,
            ),
            DesktopQualityMonitor(model: session.qualityMonitorModel),
          ],
        ),
      ),
    ));

    final canvas = tester.getRect(find.byType(Stack).first);
    final monitor = tester.getRect(find.byType(QualityMonitor));
    expect(monitor.right, canvas.right - 10);
    expect(monitor.center.dy, canvas.center.dy);
    await tester.tapAt(monitor.center);
    expect(taps, 1);
  });

  testWidgets('title-bar popup shows live network and connection details',
      (tester) async {
    final session = _Session();
    session.ffiModel.pi
      ..version = '1.5.3'
      ..platform = 'Windows';
    session.qualityMonitorModel.updateQualityStatus({
      'fps': '{"0":0}',
      'delay': '31',
      'codec_format': 'H264',
    });
    var elapsed = const Duration(minutes: 1, seconds: 15);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topRight,
          child: SessionDiagnosticsButton(
            ffi: session,
            connection: 'Relayed and encrypted connection (TCP)',
            connectedDuration: () => elapsed,
          ),
        ),
      ),
    ));
    final button = find.byType(TextButton);
    final anchorBottom = tester.getRect(button).bottom;
    expect(find.text('00:01:15'), findsOneWidget);
    expect(find.text('31 ms'), findsNothing);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text('0'), findsOneWidget);
    expect(find.text('31 ms'), findsOneWidget);
    expect(tester.getRect(find.text('31 ms')).top, greaterThan(anchorBottom));
    expect(find.text('Relayed and encrypted connection (TCP)'), findsOneWidget);
    expect(find.text('1.5.3'), findsOneWidget);
    expect(find.text('Windows'), findsOneWidget);
    expect(find.text('H264'), findsOneWidget);

    elapsed += const Duration(seconds: 1);
    session.qualityMonitorModel.updateQualityStatus({'delay': '44'});
    await tester.pump();
    expect(find.text('00:01:16'), findsOneWidget);
    expect(find.text('44 ms'), findsOneWidget);
    expect(find.text('31 ms'), findsNothing);

    await tester.tapAt(const Offset(20, 400));
    await tester.pumpAndSettle();
    expect(find.text('44 ms'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
