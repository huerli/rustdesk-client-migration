import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/widgets/peer_tab_page.dart';
import 'package:flutter_hbb/desktop/pages/desktop_home_page.dart';
import 'package:flutter_hbb/desktop/widgets/tabbar_widget.dart';
import 'package:flutter_hbb/generated_bridge.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';

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
        return '';
      case #mainGetError:
      case #mainGetLastRemoteId:
      case #mainGetOption:
        return Future.value('');
      case #mainGetMyId:
        return Future.value('123456789');
      case #mainLoadLanPeers:
      case #mainLoadRecentPeers:
      case #mainDiscover:
      case #setLocalFlutterOption:
        return Future<void>.value();
      case #mainGetConnectStatus:
        return Future.value('{"status_num":1,"video_conn_count":0}');
      case #isPresetPassword:
      case #mainIsUsingPublicServer:
        return Future.value(false);
      case #isDisableAb:
      case #isDisableAccount:
      case #isDisableGroupPanel:
      case #isDisableInstallation:
      case #mainIsCanInputMonitoring:
      case #mainIsCanScreenRecording:
      case #mainIsInstalled:
      case #mainIsInstalledDaemon:
      case #mainIsProcessTrusted:
        return true;
      case #isCustomClient:
      case #isDisableSettings:
      case #isIncomingOnly:
      case #isOutgoingOnly:
      case #isSelinuxEnforcing:
      case #mainCurrentIsWayland:
      case #mainIsLoginWayland:
      case #mainIsOptionFixed:
        return false;
    }
    return super.noSuchMethod(invocation);
  }
}

void main() {
  testWidgets('main window shows local credentials and inline ID connection',
      (tester) async {
    isTest = true;
    addTearDown(() => isTest = false);
    platformFFI.setBindingForTesting(_Binding());
    await initGlobalFFI();
    Get.put(DesktopTabController(tabType: DesktopTabType.main));
    addTearDown(() => Get.delete<DesktopTabController>());

    await tester.pumpWidget(MaterialApp(
      theme: MyTheme.lightTheme,
      home: Scaffold(
        body: ChangeNotifierProvider.value(
          value: gFFI.peerTabModel,
          child: const DesktopHomePage(),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final localId = find.text('123 456 789');
    final remoteId = find
        .byWidgetPredicate((widget) => widget is TextField && !widget.readOnly);
    expect(find.text('Your Desktop'), findsOneWidget);
    expect(localId, findsOneWidget);
    expect(find.text('One-time Password'), findsOneWidget);
    expect(find.text('Control Remote Desktop'), findsOneWidget);
    expect(remoteId, findsOneWidget);
    expect(
        tester.getRect(localId).right, lessThan(tester.getRect(remoteId).left));
    expect(find.widgetWithText(ElevatedButton, 'Connect'), findsOneWidget);
    expect(find.byType(PeerTabPage), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
  });
}
