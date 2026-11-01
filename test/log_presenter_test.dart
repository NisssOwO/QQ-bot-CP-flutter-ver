import 'package:flutter_test/flutter_test.dart';
import 'package:qq_bot_cp/src/models/runtime_log.dart';
import 'package:qq_bot_cp/src/services/log_presenter.dart';

RuntimeLogEntry entry(String message, {LogLevel level = LogLevel.info, String module = 'runtime'}) =>
    RuntimeLogEntry(time: DateTime(2026, 11, 1), level: level, module: module, message: message);

void main() {
  test('rewrites plugin noise into a readable sentence and keeps the raw text', () {
    final presentation = presentLog(entry('plugin-manager (@deepseek-ai/dsh-plugin-manager): failed to import: SyntaxError: Invalid regular expression'));

    expect(presentation.message, '有一个可选插件没有加载，不影响聊天');
    expect(presentation.detail, contains('SyntaxError'));
  });

  test('maps the three runtime states a user actually waits for', () {
    expect(presentLog(entry('[im-qqbot] Bot ready! appId=100000000')).message, 'QQ 机器人已连接，可以开始聊天');
    expect(presentLog(entry('restart.complete 启动流程完成')).message, '启动完成');
    expect(presentLog(entry('im-qqbot: preset fallback applied key=group:123')).message, '已把当前角色卡应用到这批旧会话');
  });

  test('paints a pending plugin as information instead of an error', () {
    final presentation = presentLog(entry('tool-workflow: pending (waiting for service: workflowEngine)', level: LogLevel.error, module: 'node'));

    expect(presentation.message, '部分插件在等待依赖，启动完成后会自动生效');
    expect(presentation.level, LogLevel.info);
  });

  test('leaves ordinary messages untouched and without a detail block', () {
    final presentation = presentLog(entry('收到群消息，准备回复'));

    expect(presentation.message, '收到群消息，准备回复');
    expect(presentation.detail, isNull);
  });

  test('stamps every row with the clock and keeps the date for older rows', () {
    final now = DateTime(2026, 11, 1, 18, 30);

    expect(formatLogTime(DateTime(2026, 11, 1, 9, 5, 7), now: now), '09:05:07');
    expect(formatLogTime(DateTime(2026, 10, 31, 23, 59, 1), now: now), '10-31 23:59:01');
  });
}
