import 'package:flutter_test/flutter_test.dart';
import 'package:qq_bot_cp/src/models/proactive_reply.dart';

void main() {
  test('group overrides store only fields that differ from global', () {
    const config = ProactiveReplyConfig();
    final next = config.withGroup(
        'g1', config.global.withValue('probability', 30));
    expect(next.groups['g1'], {'probability': 30});
  });

  test('changing global flows into groups without that field overridden', () {
    final config = const ProactiveReplyConfig()
        .withGroup('g1', const ProactiveReplySettings(probability: 30));
    final next = config.withGlobal(const ProactiveReplySettings(
        enabled: true, cooldownSeconds: 60));
    final g1 = next.effective('g1');
    expect(g1.enabled, isTrue);
    expect(g1.cooldownSeconds, 60);
    expect(g1.probability, 30);
  });

  test('saving a group identical to global removes the override', () {
    final config = const ProactiveReplyConfig()
        .withGroup('g1', const ProactiveReplySettings(probability: 30));
    final next = config.withGroup('g1', config.global);
    expect(next.groups.containsKey('g1'), isFalse);
  });

  test('legacy full-copy group configs are reduced to a diff', () {
    final config = ProactiveReplyConfig.fromJson({
      'schemaVersion': 1,
      'global': {'probability': 5},
      'groups': {
        'g1': {'probability': 5, 'minMessages': 7, 'model': 'deepseek-v4.1'}
      }
    });
    expect(config.groups['g1'], {'minMessages': 7});
  });

  test('values are clamped to the Node ranges', () {
    final s = ProactiveReplySettings.fromJson(
        {'minTextLength': 0, 'maxTextLength': 9000, 'historyMessages': 500});
    expect(s.minTextLength, 1);
    expect(s.maxTextLength, 5000);
    expect(s.historyMessages, 100);
    expect(s.toJson().containsKey('model'), isFalse);
  });

  test('status counts only today and sorts by last activity', () {
    final now = DateTime(2026, 11, 12, 16);
    final list = ProactiveReplyGroupStatus.listFromJson({
      'groups': {
        'old': {'day': '2026-11-11', 'count': 9, 'lastSeen': 1000},
        'new': {
          'day': '2026-11-12',
          'count': 2,
          'lastSeen': now.millisecondsSinceEpoch
        },
      }
    }, now: now);
    expect(list.map((e) => e.groupId), ['new', 'old']);
    expect(list.first.today, 2);
    expect(list.last.today, 0);
  });

  test('runtime status reads requireMention, time zone and test result', () {
    final now = DateTime(2026, 11, 12, 16);
    final offset = now.timeZoneOffset.inMinutes;
    final status = ProactiveReplyRuntimeStatus.fromJson({
      'schemaVersion': 1,
      'requireMention': false,
      'timeZone': 'Asia/Shanghai',
      'utcOffsetMinutes': offset,
      'groups': {
        'G1': {
          'sinceReply': 4,
          'lastTestId': 't1',
          'lastTestResult': '测试已发送：你好',
          'lastTest': now.millisecondsSinceEpoch
        }
      }
    }, now: now);
    expect(status.loaded, isTrue);
    expect(status.requireMention, isFalse);
    expect(status.timeZoneMismatch(now), isFalse);
    final g = status.group('G1')!;
    expect(g.sinceReply, 4);
    expect(g.lastTestId, 't1');
    expect(g.lastTestResult, startsWith('测试已发送'));
    expect(status.group('missing'), isNull);
  });

  test('runtime status defaults when Node has not written the file', () {
    final status = ProactiveReplyRuntimeStatus.fromJson({'groups': {}});
    expect(status.loaded, isFalse);
    expect(status.requireMention, isTrue);
    expect(status.timeZoneMismatch(DateTime.now()), isFalse);
    expect(
        const ProactiveReplyRuntimeStatus(utcOffsetMinutes: 480).timeZoneLabel,
        'UTC+08:00');
    expect(
        const ProactiveReplyRuntimeStatus(
                timeZone: 'America/New_York', utcOffsetMinutes: -300)
            .timeZoneLabel,
        'America/New_York UTC-05:00');
  });
}
