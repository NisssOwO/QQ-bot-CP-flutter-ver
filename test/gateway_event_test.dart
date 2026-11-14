import 'package:flutter_test/flutter_test.dart';
import 'package:qq_bot_cp/src/models/gateway_event.dart';

void main() {
  group('GatewayEventEntry', () {
    test('区分本地判定与服务端关闭帧', () {
      final local = GatewayEventEntry.fromMap({
        'ts': 1763000000000,
        'event': 'reconnecting',
        'code': 1000,
        'codeSource': 'local',
        'codeName': 'ready_timeout',
        'codeText': '（本地判定，非服务端关闭帧）',
        'uptimeMs': 18500,
      });
      expect(local.fromServer, isFalse);
      expect(local.isRecovering, isTrue);
      expect(local.codeName, 'ready_timeout');
      expect(local.uptimeMs, 18500);

      final server = GatewayEventEntry.fromMap({
        'ts': 1763000000000,
        'event': 'offline',
        'code': 4004,
        'codeSource': 'server',
        'codeName': 'auth_failed',
        'codeText': '鉴权失败',
      });
      expect(server.fromServer, isTrue);
      expect(server.isFailure, isTrue);
      expect(server.code, 4004);
    });

    test('缺字段时回退到 iso 和空值，不抛异常', () {
      final entry = GatewayEventEntry.fromMap({
        'iso': '2026-11-14T08:00:00.000Z',
        'event': 'online',
      });
      expect(entry.event, 'online');
      expect(entry.code, isNull);
      expect(entry.uptimeMs, isNull);
      expect(entry.time.toUtc().hour, 8);
      expect(entry.isHealthy, isTrue);
    });

    test('完全空的对象也能解析', () {
      final entry = GatewayEventEntry.fromMap(const {});
      expect(entry.event, 'unknown');
      expect(entry.isFailure, isFalse);
      expect(entry.raw, isEmpty);
    });

    test('message 缺失时回退到 detail', () {
      final entry = GatewayEventEntry.fromMap({'event': 'failed', 'detail': 'auth failed'});
      expect(entry.message, 'auth failed');
    });
  });

  group('GatewayEventLog', () {
    test('解析事件列表与总行数', () {
      final log = GatewayEventLog.fromMap({
        'path': '/data/user/0/pkg/files/runtime/logs/gateway-events.jsonl',
        'lines': 42,
        'events': [
          {'ts': 1, 'event': 'start', 'message': 'Runtime 启动'},
          {'ts': 2, 'event': 'online'},
        ],
      });
      expect(log.path, endsWith('gateway-events.jsonl'));
      expect(log.lines, 42);
      expect(log.events.length, 2);
      expect(log.isEmpty, isFalse);
    });

    test('空结果不抛异常', () {
      final log = GatewayEventLog.fromMap(const {'path': '', 'lines': 0, 'events': []});
      expect(log.isEmpty, isTrue);
      expect(const GatewayEventLog.empty().isEmpty, isTrue);
    });
  });
}
