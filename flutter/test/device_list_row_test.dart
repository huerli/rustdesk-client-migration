import 'package:flutter/material.dart';
import 'package:flutter_hbb/desktop/widgets/device_list_row.dart';
import 'package:flutter_hbb/generated_bridge.dart';
import 'package:flutter_hbb/models/peer_model.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_test/flutter_test.dart';

class _Binding extends Fake implements RustdeskImpl {
  @override
  String translate(
          {required String name, required String locale, dynamic hint}) =>
      name;
}

void main() {
  setUp(() => platformFFI.setBindingForTesting(_Binding()));

  testWidgets('device row shows its name, ID and status and connects',
      (tester) async {
    var connected = false;
    final peer = Peer.fromJson({
      'id': '123456789',
      'alias': 'Office PC',
      'hostname': 'desktop-office',
      'username': 'admin',
      'platform': 'Windows',
    })
      ..online = true;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 580,
          height: 74,
          child: DeviceListRow(
            peer: peer,
            onConnect: () => connected = true,
            actions: const Icon(Icons.more_vert),
          ),
        ),
      ),
    ));
    expect(find.text('Office PC'), findsOneWidget);
    expect(find.text('123 456 789 · admin'), findsOneWidget);
    expect(find.text('Online'), findsOneWidget);
    expect(find.byIcon(Icons.more_vert), findsOneWidget);
    await tester.tap(find.byTooltip('Connect'));
    expect(connected, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow device row fits a long name and hides the username',
      (tester) async {
    final peer = Peer.fromJson({
      'id': '123456789',
      'hostname': 'desktop-with-a-long-device-name-for-a-small-window',
      'username': 'private-user',
      'platform': 'Linux',
    });
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(
        body: SizedBox(
          width: 320,
          height: 74,
          child: DeviceListRow(
            peer: peer,
            hideUsername: true,
            onConnect: () {},
            actions: const Icon(Icons.more_vert),
          ),
        ),
      ),
    ));
    expect(find.text('123 456 789'), findsOneWidget);
    expect(find.textContaining('private-user'), findsNothing);
    expect(find.byTooltip('Offline'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
