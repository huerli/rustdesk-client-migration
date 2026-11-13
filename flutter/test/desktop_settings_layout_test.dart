import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/desktop/pages/desktop_setting_page.dart';
import 'package:flutter_hbb/generated_bridge.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_test/flutter_test.dart';

class _Binding extends Fake implements RustdeskImpl {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    switch (invocation.memberName) {
      case #translate:
        return invocation.namedArguments[#name];
      case #mainGetBuildinOption:
      case #mainGetLocalOption:
      case #mainGetOptionSync:
      case #getLocalFlutterOption:
      case #mainGetUnlockPin:
        return '';
      case #mainSupportedPrivacyModeImpls:
        return '[]';
      case #mainIsInstalled:
        return true;
      case #isOutgoingOnly:
      case #isIncomingOnly:
      case #isDisableSettings:
      case #isDisableAccount:
      case #isDisableAb:
      case #isDisableGroupPanel:
      case #isCustomClient:
      case #mainIsOptionFixed:
      case #mainHasValid2FaSync:
      case #mainHasValidBotSync:
      case #mainIsShareRdp:
        return false;
      case #mainIsUsingPublicServer:
        return Future.value(false);
      case #mainGetCommon:
        return Future.value('true');
    }
    return super.noSuchMethod(invocation);
  }
}

void main() {
  testWidgets(
      'security and network unlock buttons share the card header layout',
      (tester) async {
    isTest = true;
    addTearDown(() => isTest = false);
    platformFFI.setBindingForTesting(_Binding());
    await initGlobalFFI();
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    for (final width in [1218.0, 768.0]) {
      tester.view.physicalSize = Size(width, 820);
      final buttonSizes = <Size>[];
      for (final tab in [SettingsTabKey.safety, SettingsTabKey.network]) {
        await tester.pumpWidget(MaterialApp(
          theme: MyTheme.lightTheme,
          home: DesktopSettingPage(initialTabkey: tab),
        ));
        await tester.pump(const Duration(milliseconds: 1));
        expect(tester.takeException(), isNull);
        final label = tab == SettingsTabKey.safety
            ? 'Unlock Security Settings'
            : 'Unlock Network Settings';
        final title = tab == SettingsTabKey.safety ? 'Permissions' : 'Network';
        final button = find.ancestor(
            of: find.text(label),
            matching:
                find.byWidgetPredicate((widget) => widget is OutlinedButton));
        expect(button, findsOneWidget);
        final card =
            find.ancestor(of: find.text(title), matching: find.byType(Card));
        expect(find.descendant(of: card, matching: button), findsOneWidget);
        final buttonRect = tester.getRect(button);
        final titleRect = tester
            .getRect(find.descendant(of: card, matching: find.text(title)));
        expect(buttonRect.center.dy, closeTo(titleRect.center.dy, 0.1));
        expect(buttonRect.left, greaterThanOrEqualTo(titleRect.right));
        buttonSizes.add(buttonRect.size);
        await tester.pumpWidget(const SizedBox());
      }
      expect(buttonSizes[0].height, closeTo(buttonSizes[1].height, 0.1));
    }
  });
}
