import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/generated_bridge.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_test/flutter_test.dart';

class _Binding extends Fake implements RustdeskImpl {
  var result = Completer<bool>();

  @override
  Future<bool> isPresetPassword({dynamic hint}) => result.future;

  @override
  String mainGetBuildinOption({required String key, dynamic hint}) => 'N';

  @override
  String translate(
          {required String name, required String locale, dynamic hint}) =>
      name;
}

void main() {
  testWidgets('security warning stays steady while the check refreshes',
      (tester) async {
    final binding = _Binding();
    platformFFI.setBindingForTesting(binding);

    Future<void> rebuild() =>
        tester.pumpWidget(MaterialApp(home: buildPresetPasswordWarning()));

    final spinner = find.byType(CircularProgressIndicator);
    final warning = find.text('Security Alert');
    await rebuild();
    expect(spinner, findsOneWidget);

    binding.result.complete(false);
    await tester.pumpAndSettle();
    expect(warning, findsNothing);

    binding.result = Completer<bool>();
    await rebuild();
    expect(spinner, findsNothing);
    expect(warning, findsNothing);

    binding.result.complete(true);
    await tester.pumpAndSettle();
    expect(warning, findsOneWidget);

    binding.result = Completer<bool>();
    await rebuild();
    expect(spinner, findsNothing);
    expect(warning, findsOneWidget);

    binding.result.complete(false);
    await tester.pumpAndSettle();
    expect(warning, findsNothing);
  });
}
