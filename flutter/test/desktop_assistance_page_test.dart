import 'package:flutter/material.dart';
import 'package:flutter_hbb/desktop/pages/desktop_assistance_page.dart';
import 'package:flutter_hbb/generated_bridge.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

class _Binding extends Fake implements RustdeskImpl {
  @override
  bool isOutgoingOnly({dynamic hint}) => true;

  @override
  String translate(
          {required String name, required String locale, dynamic hint}) =>
      name;
}

void main() {
  testWidgets('assistance shows an inline form and requires a partner ID',
      (tester) async {
    platformFFI.setBindingForTesting(_Binding());
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: DesktopAssistancePage(serviceStopped: false.obs)),
    ));

    final connect = find.widgetWithText(ElevatedButton, 'Connect');
    expect(find.text('Remote assistance'), findsOneWidget);
    expect(find.text('Your Device'), findsNothing);
    expect(find.byType(Dialog), findsNothing);
    expect(tester.widget<ElevatedButton>(connect).onPressed, isNull);

    await tester.enterText(find.byType(TextField), '123456789');
    await tester.pump();
    expect(find.text('123 456 789'), findsOneWidget);
    expect(tester.widget<ElevatedButton>(connect).onPressed, isNotNull);

    await tester.enterText(find.byType(TextField), '');
    await tester.pump();
    expect(tester.widget<ElevatedButton>(connect).onPressed, isNull);
  });
}
