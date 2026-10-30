import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qq_bot_cp/main.dart';

void main() {
  testWidgets('starts with empty-config overview', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('qq_bot_cp/runtime'), (call) async {
      switch (call.method) {
        case 'getThemeSettings':
          return <String, Object?>{'mode': 'dark', 'seedColor': 0xff8290ff, 'cardRadius': 16.0, 'cardOpacity': 1.0, 'tintedBackground': false};
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
    expect(find.text('设备公网 IP'), findsOneWidget);
    expect(find.text('等待填写 AppID 与 AppSecret'), findsOneWidget);
    await tester.drag(find.byType(ListView).first, const Offset(0, -700));
    await tester.pump();
    expect(find.textContaining('API Key'), findsOneWidget);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('qq_bot_cp/runtime'), null);
  });
}
