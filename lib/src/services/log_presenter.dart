import '../models/runtime_log.dart';

/// A log line as the user should read it.
///
/// [message] is the short, plain description shown as the headline. When the
/// runtime wrote something machine-shaped (a stack trace, a missing module, a
/// plugin that failed to import), [detail] keeps the original text so it can
/// still be inspected without pushing raw noise into the main column.
class LogPresentation {
  const LogPresentation(this.message, {required this.level, this.detail, this.muted = false});
  final String message;

  /// The level the runtime actually reported. It is never rewritten here: the
  /// level filter and the row colour have to agree, otherwise the 警告 filter
  /// returns nothing while warnings are painted green.
  final LogLevel level;

  /// Optional-plugin noise keeps its level but is painted in a neutral colour,
  /// so a warning caused by a plugin we deliberately disabled does not look
  /// like a chat failure.
  final bool muted;
  final String? detail;
}

/// Patterns that describe optional runtime plumbing rather than a chat failure.
final List<RegExp> _harmless = [
  RegExp(r'plugin-manager.*failed to import'),
  RegExp(r'ERR_MODULE_NOT_FOUND'),
  RegExp(r'pending \(waiting for service'),
  RegExp(r'did not activate'),
  RegExp(r'InterruptedIOException'),
];

/// Runtime messages that used to surface as-is but mean nothing to a user.
/// Order matters: the first rule that matches wins.
final List<(RegExp, String)> _rules = [
  (RegExp(r'^\[inbound\]\s*'), ''),
  (RegExp(r'^\[outbound\]\s*'), ''),
  (RegExp(r'Bot ready!'), 'QQ 机器人已连接，可以开始聊天'),
  (RegExp(r'^restart\.complete'), '启动完成'),
  (RegExp(r'preset fallback applied'), '已把当前角色卡应用到这批旧会话'),
  (RegExp(r'plugin-manager.*failed to import'), '有一个可选插件没有加载，不影响聊天'),
  (RegExp(r'ERR_MODULE_NOT_FOUND'), '有可选依赖缺失，相关附加功能不可用'),
  (RegExp(r'pending \(waiting for service'), '部分插件在等待依赖，启动完成后会自动生效'),
  (RegExp(r'did not activate'), '部分可选插件没有启用，不影响使用'),
  (RegExp(r'InterruptedIOException'), '后台线程被主动关闭，已忽略'),
];

LogPresentation presentLog(RuntimeLogEntry entry) {
  final raw = entry.message;
  final muted = _harmless.any((pattern) => pattern.hasMatch(raw));
  for (final rule in _rules) {
    if (!rule.$1.hasMatch(raw)) continue;
    // 收发消息的行自带中文说明，只需去掉给机器看的标签。
    if (rule.$2.isEmpty) {
      final text = raw.replaceFirst(rule.$1, '');
      return LogPresentation(text, level: entry.level, muted: muted, detail: text == raw ? null : raw);
    }
    // A clean headline needs no detail block; only keep the raw text when it
    // still carries information the user could act on.
    return LogPresentation(rule.$2, level: entry.level, muted: muted, detail: raw == rule.$2 ? null : raw);
  }
  return LogPresentation(raw, level: entry.level, muted: muted);
}

/// Timestamp shown on every log row. Rows older than today keep their date so a history
/// that survived a restart still reads in order.
String formatLogTime(DateTime time, {DateTime? now}) {
  final reference = now ?? DateTime.now();
  String two(int value) => value.toString().padLeft(2, '0');
  final clock = '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
  final sameDay = time.year == reference.year && time.month == reference.month && time.day == reference.day;
  return sameDay ? clock : '${two(time.month)}-${two(time.day)} $clock';
}