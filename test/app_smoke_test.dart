import 'package:flutter_test/flutter_test.dart';
import 'package:qq_bot_cp_flutter/main.dart';

void main() {
  testWidgets('starts with empty-config overview', (tester) async {
    await tester.pumpWidget(const QqBotCpApp());
    expect(find.text('QQ-bot-CP'), findsOneWidget);
    expect(find.text('设备公网 IP'), findsOneWidget);
    expect(find.text('默认空配置，等待填写'), findsOneWidget);
  });
}
