import '../models/runtime_log.dart';

/// A log line as the user should read it.
///
/// [message] is the short, plain description shown as the headline. When the
/// runtime wrote something machine-shaped (a stack trace, a missing module, a
/// plugin that failed to import), [detail] keeps the original text so it can
/// still be inspected without pushing raw noise into the main column.
class LogPresentation {
  const LogPresentation(this.message, {required this.level, this.detail});
  final String message;

  /// The level to paint the row with. Some runtime messages arrive as errors
  /// but only describe an optional plugin waiting for a service, so they are
  /// shown as information instead of a red failure.
  final LogLevel level;
  final String? detail;
}

/// Patterns whose original level is an error but which do not affect chatting.
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
  final level = _harmless.any((pattern) => pattern.hasMatch(raw)) ? LogLevel.info : entry.level;
  for (final rule in _rules) {
    if (!rule.$1.hasMatch(raw)) continue;
    // A clean headline needs no detail block; only keep the raw text when it
    // still carries information the user could act on.
    return LogPresentation(rule.$2, level: level, detail: raw == rule.$2 ? null : raw);
  }
  return LogPresentation(raw, level: level);
}