import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/widgets/setting_widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('trackpad speed input fits a narrow settings row',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 240,
          child: TrackpadSpeedWidget(value: SimpleWrapper(100)),
        ),
      ),
    ));

    expect(find.text('100'), findsOneWidget);
    expect(find.text('%'), findsOneWidget);
    expect(tester.takeException(), isNull);
    final row = tester.getRect(find.byType(TrackpadSpeedWidget));
    expect(tester.getRect(find.text('%')).right, lessThanOrEqualTo(row.right));
  });
}
