import 'package:flutter_test/flutter_test.dart';
import 'package:qq_bot_cp/src/models/runtime_log.dart';
import 'package:qq_bot_cp/src/services/startup_stats.dart';

RuntimeLogEntry entry(String message, {int? elapsedMs, String? runId, String module = 'runtime'}) =>
    RuntimeLogEntry(time: DateTime(2026, 11, 1), level: LogLevel.info, module: module, message: message, elapsedMs: elapsedMs, runId: runId);

void main() {
  test('keeps the slow unpacking run out of the normal startup average', () {
    final stats = summarizeStartup([
      entry('开始启动（runId=aaaa1111，来源=user）', runId: 'aaaa1111'),
      entry('运行文件就绪（解包 assets，耗时 312 秒）', runId: 'aaaa1111'),
      entry('restart.complete 启动流程完成', elapsedMs: 314000, runId: 'aaaa1111'),
      entry('开始启动（runId=bbbb2222，来源=user）', runId: 'bbbb2222'),
      entry('运行文件就绪（解包 assets，耗时 0 秒）', runId: 'bbbb2222'),
      entry('restart.complete 启动流程完成', elapsedMs: 420, runId: 'bbbb2222'),
      entry('restart.complete 启动流程完成', elapsedMs: 380, runId: 'bbbb2222'),
    ]);

    expect(stats.unpacked, [314000]);
    expect(stats.cached, [420, 380]);
    expect(stats.unpackedAverage, 314000);
    expect(stats.cachedAverage, 400);
    expect(stats.lastMs, 380);
    expect(stats.lastUnpacked, isFalse);
    expect(stats.isEmpty, isFalse);
  });

  test('labels a long run as unpacking and counts reconnect retries', () {
    final stats = summarizeStartup([
      entry('运行文件就绪（解包 assets，耗时 95 秒）', runId: 'cccc3333'),
      entry('restart.complete 启动流程完成', elapsedMs: 96000, runId: 'cccc3333'),
      entry('第 1 次重连，1 秒后检查', module: 'network'),
      entry('第 2 次重连，2 秒后检查', module: 'network'),
      entry('Runtime 进程已恢复', module: 'network'),
    ]);

    expect(stats.lastMs, 96000);
    expect(stats.lastUnpacked, isTrue);
    expect(stats.cachedAverage, isNull);
    expect(stats.reconnects, 2);
  });

  test('ignores runs without a duration and reports empty state', () {
    expect(summarizeStartup(const []).isEmpty, isTrue);
    final stats = summarizeStartup([
      entry('restart.complete 启动流程完成', runId: 'dddd4444'),
      entry('重启中'),
    ]);
    expect(stats.isEmpty, isTrue);
    expect(stats.reconnects, 0);
  });
}