import 'dart:convert';

import 'package:flutter_hbb/common/widgets/peer_card.dart';
import 'package:flutter_hbb/models/peer_model.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('LAN discovery keeps scan status and clears it when a peer goes offline',
      () async {
    final peers = Peers(
        name: 'lan_online_test', getInitPeers: null, loadEvent: 'load_lan_peers');
    addTearDown(peers.dispose);
    Future<void> load(bool online) async {
      await platformFFI.tryHandle({
        'name': 'load_lan_peers',
        'peers': jsonEncode([
          {'id': '123456789', 'online': '$online', 'ip_addresses': '192.168.1.20'}
        ]),
      });
    }

    await load(true);
    expect(peers.peers.single.online, isTrue);
    expect(peers.peers.single.ipAddresses, '192.168.1.20');
    await platformFFI.tryHandle({
      'name': 'callback_query_onlines',
      'onlines': '',
      'offlines': '123456789',
    });
    expect(peers.peers.single.online, isTrue);
    await load(false);
    expect(peers.peers.single.online, isFalse);
  });

  test('recent devices use LAN ID or IP status without retaining it in history',
      () {
    final recent = [
      Peer.fromJson({'id': '123456789'}),
      Peer.fromJson({'id': '192.168.1.20'}),
      Peer.fromJson({'id': '987654321'})..online = true,
    ];
    final lan = Peer.fromJson({'id': '123456789'})
      ..online = true
      ..ipAddresses = '192.168.1.20,10.0.0.20';

    Iterable<bool> displayStatus() =>
        recent.map((peer) => peerWithLanStatus(peer, [lan]).online);

    expect(displayStatus(), [true, true, true]);
    expect(recent.map((peer) => peer.online), [false, false, true]);
    lan.online = false;
    expect(displayStatus(), [false, false, true]);
  });
}
