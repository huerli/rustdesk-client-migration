import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart' show initGlobalFFI, isTest;
import 'package:flutter_hbb/desktop/pages/desktop_assistance_page.dart';
import 'package:flutter_hbb/generated_bridge.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

class _Binding extends Fake implements RustdeskImpl {
  _Binding({this.outgoingOnly = true});

  final bool outgoingOnly;

  @override
  bool isOutgoingOnly({dynamic hint}) => outgoingOnly;

  @override
  bool isDisableSettings({dynamic hint}) => true;
  @override
  bool isDisableAb({dynamic hint}) => true;
  @override
  bool isDisableAccount({dynamic hint}) => true;
  @override
  bool isDisableGroupPanel({dynamic hint}) => true;
  @override
  bool mainIsOptionFixed({required String key, dynamic hint}) => false;
  @override
  String mainGetLocalOption({required String key, dynamic hint}) => '';
  @override
  String mainGetBuildinOption({required String key, dynamic hint}) => '';
  @override
  String getLocalFlutterOption({required String k, dynamic hint}) => '';

  @override
  String translate(
          {required String name, required String locale, dynamic hint}) =>
      name;
}

void main() {
  testWidgets('incoming service status fits a narrow assistance pane',
      (tester) async {
    platformFFI.setBindingForTesting(_Binding(outgoingOnly: false));
    isTest = true;
    addTearDown(() => isTest = false);
    await initGlobalFFI();
    await tester.binding.setSurfaceSize(const Size(360, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: DesktopAssistancePage(serviceStopped: false.obs)),
    ));

    expect(find.text('Incoming connection'), findsOneWidget);
    expect(find.text('Service is running'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, skip: !isLinux);

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
