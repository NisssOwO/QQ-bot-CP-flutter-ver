import 'package:flutter_test/flutter_test.dart';
import 'package:qq_bot_cp/src/models/gateway_status.dart';

void main() {
  test('unknown state when the file never existed', () {
    const status = GatewayStatus();
    expect(status.kind, GatewayState.unknown);
    expect(status.hasData, isFalse);
    expect(status.heartbeatStale(DateTime(2026)), isFalse);
    expect(status.connectedFor(DateTime(2026)), isNull);
  });

  test('parses a live gateway snapshot and computes uptime', () {
    final updated = DateTime(2026, 11, 12, 23, 0, 0);
    final status = GatewayStatus.fromMap(<String, Object?>{
      'state': 'online',
      'appId': '102000000',
      'since': updated.subtract(const Duration(minutes: 12)).millisecondsSinceEpoch,
      'updatedAt': updated.millisecondsSinceEpoch,
      'attempts': 2,
      'code': 0,
      'reason': '',
      'error': '',
      'lastError': '',
    });

    expect(status.kind, GatewayState.online);
    expect(status.kind.isUp, isTrue);
    expect(status.hasData, isTrue);
    expect(status.heartbeatStale(updated.add(const Duration(seconds: 30))), isFalse);
    expect(status.connectedFor(updated.add(const Duration(seconds: 30)))?.inMinutes, 12);
    expect(status.code, 0);
    expect(status.attempts, 2);
  });

  test('online but silent heartbeat is reported as stale', () {
    final updated = DateTime(2026, 11, 12, 23, 0, 0);
    final status = GatewayStatus.fromMap(<String, Object?>{
      'state': 'online',
      'updatedAt': updated.millisecondsSinceEpoch,
      'since': updated.millisecondsSinceEpoch,
    });

    // 90 秒以内仍算在线，超过就说明这条连接没人维护了。
    expect(status.heartbeatStale(updated.add(const Duration(seconds: 80))), isFalse);
    expect(status.heartbeatStale(updated.add(const Duration(seconds: 120))), isTrue);
    expect(status.connectedFor(updated.add(const Duration(seconds: 120))), isNull);
  });

  test('offline and failed states carry diagnostic codes', () {
    final offline = GatewayStatus.fromMap(<String, Object?>{
      'state': 'offline',
      'updatedAt': 1700000000000,
      'code': 4914,
      'reason': 'insufficient intents',
    });
    expect(offline.kind, GatewayState.offline);
    expect(offline.kind.isBad, isTrue);
    expect(offline.code, 4914);
    expect(offline.reason, 'insufficient intents');

    final failed = GatewayStatus.fromMap(<String, Object?>{
      'state': 'failed',
      'updatedAt': 1700000000000,
      'error': 'bot.start() rejected',
    });
    expect(failed.kind, GatewayState.failed);
    expect(failed.error, 'bot.start() rejected');
  });

  test('reconnecting counts attempts and keeps a message', () {
    final status = GatewayStatus.fromMap(<String, Object?>{
      'state': 'reconnecting',
      'updatedAt': 1700000000000,
      'attempts': 5,
      'code': 4009,
    });
    expect(status.kind, GatewayState.reconnecting);
    expect(status.attempts, 5);
    expect(status.kind.isUp, isFalse);
    expect(status.kind.isBad, isFalse);
  });
}