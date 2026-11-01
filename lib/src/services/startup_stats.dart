import '../models/runtime_log.dart';

/// Startup timings split by what actually happened during the run.
///
/// A first launch spends minutes unpacking the runtime, so mixing it with the
/// sub-second launches that follow would make the estimate useless.
class StartupStats {
  const StartupStats({
    required this.unpacked,
    required this.cached,
    required this.reconnects,
    required this.lastMs,
    required this.lastUnpacked,
  });

  /// Durations of runs whose log contains a finished asset extraction.
  final List<int> unpacked;

  /// Durations of runs that started on an already unpacked runtime.
  final List<int> cached;

  /// Number of reconnect attempts recorded in the same log window.
  final int reconnects;

  /// Duration of the most recent completed run, whatever bucket it fell into.
  final int? lastMs;

  /// Whether the most recent completed run had to unpack the runtime.
  final bool lastUnpacked;

  static const StartupStats empty = StartupStats(
    unpacked: [],
    cached: [],
    reconnects: 0,
    lastMs: null,
    lastUnpacked: false,
  );

  bool get isEmpty => lastMs == null;

  int? get unpackedAverage => _average(unpacked);
  int? get cachedAverage => _average(cached);

  static int? _average(List<int> values) {
    if (values.isEmpty) return null;
    return (values.reduce((a, b) => a + b) / values.length).round();
  }
}

/// Splits every completed start into an "unpacked" and a "cached" bucket.
StartupStats summarizeStartup(Iterable<RuntimeLogEntry> logs) {
  final entries = logs.toList();
  final unpackedRuns = <String>{};
  for (final entry in entries) {
    final runId = entry.runId;
    if (runId != null && _extractionSeconds(entry.message) != null) unpackedRuns.add(runId);
  }
  final unpacked = <int>[];
  final cached = <int>[];
  var reconnects = 0;
  int? lastMs;
  var lastUnpacked = false;
  for (final entry in entries) {
    if (_reconnectAttempt.hasMatch(entry.message)) reconnects++;
    if (!entry.message.startsWith('restart.complete')) continue;
    final value = entry.elapsedMs;
    if (value == null || value <= 0) continue;
    final runId = entry.runId;
    final isUnpacked = runId != null && unpackedRuns.contains(runId);
    if (isUnpacked) {
      unpacked.add(value);
    } else {
      cached.add(value);
    }
    lastMs = value;
    lastUnpacked = isUnpacked;
  }
  return StartupStats(
    unpacked: unpacked,
    cached: cached,
    reconnects: reconnects,
    lastMs: lastMs,
    lastUnpacked: lastUnpacked,
  );
}

/// Seconds spent unpacking, parsed from "运行文件就绪（解包 assets，耗时 123 秒）".
/// A cached start rewrites the same line with 0 秒, which must not count as unpacking.
int? _extractionSeconds(String message) {
  if (!message.startsWith('运行文件就绪')) return null;
  final match = RegExp(r'耗时 (\d+) 秒').firstMatch(message);
  final seconds = int.tryParse(match?.group(1) ?? '');
  return seconds == null || seconds < 1 ? null : seconds;
}

final RegExp _reconnectAttempt = RegExp(r'第 \d+ 次重连');