import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:qq_bot_cp/main.dart';

void main() {
  testWidgets('starts with empty-config overview', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('qq_bot_cp/runtime'), (call) async {
      switch (call.method) {
        case 'getThemeSettings':
          return <String, Object?>{'mode': 'dark', 'seedColor': 0xff0e7490, 'cardRadius': 16.0, 'cardOpacity': 0.85, 'tintedBackground': true};
        case 'getRuntimeState':
          return <String, Object?>{'status': 'stopped', 'phase': 'stopped', 'message': '', 'elapsedMs': 0};
        case 'getPublicConfig':
          return <String, Object?>{'protocol': '', 'model': '', 'baseUrl': '', 'appId': '', 'qqConfigured': false, 'llmConfigured': false};
        default:
          return null;
      }
    });
    await tester.pumpWidget(const QqBotCpApp());
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('QQ-bot-CP'), findsOneWidget);
    expect(find.text('Runtime 控制'), findsOneWidget);
    expect(find.textContaining('重启'), findsWidgets);

    await tester.tap(find.text('AI').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('API Key'), findsWidgets);

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('qq_bot_cp/runtime'), null);
  });
}