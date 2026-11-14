/// 一条网关事件流水。
///
/// 来源是 Node 侧只追加写入的 `gateway-events.jsonl`，和 `gateway-status.json`
/// 的分工是「历史 vs 快照」：快照只有最后一次失败，流水每次断开都留一行。
class GatewayEventEntry {
  const GatewayEventEntry({
    required this.time,
    required this.event,
    this.code,
    this.codeSource,
    this.codeName,
    this.codeText,
    this.reason,
    this.uptimeMs,
    this.sinceLastReadyMs,
    this.attempt,
    this.message,
    this.raw = const {},
  });

  /// 事件发生时间。
  final DateTime time;

  /// 事件类型：`reconnecting` / `offline` / `online` / `failed` / `start` / `stop` / `unparsed`。
  final String event;

  /// WebSocket 关闭码。本地判定时这个码是 SDK 自己构造的，不代表服务端真的发了。
  final int? code;

  /// `server` 表示真的收到了服务端关闭帧；`local` 表示 SDK 本地判定超时/异常。
  final String? codeSource;

  /// 稳定的语义 key，如 `ready_timeout`、`heartbeat_timeout`、`auth_failed`。
  final String? codeName;

  /// 中文释义，区分「本地判定」和「服务端关闭」。
  final String? codeText;

  /// SDK 给的原始原因文本。
  final String? reason;

  /// 本次连接存活时长。
  final int? uptimeMs;

  /// 距离上一次 READY 隔了多久。
  final int? sinceLastReadyMs;

  /// 这是第几次重连尝试。
  final int? attempt;

  /// `start` / `stop` / `failed` 等事件的说明文本。
  final String? message;

  /// 原始字段，导出时按原样写回 JSONL。
  final Map<String, Object?> raw;

  /// 是否来自服务端真实关闭帧（而不是 SDK 本地判定）。
  bool get fromServer => codeSource == 'server';

  /// 是否属于「断开」类事件，决定列表里的配色。
  bool get isFailure => event == 'offline' || event == 'failed' || event == 'unparsed';

  bool get isRecovering => event == 'reconnecting';

  bool get isHealthy => event == 'online';

  factory GatewayEventEntry.fromMap(Map raw) {
    final ts = raw['ts'];
    final iso = raw['iso'];
    DateTime time;
    if (ts is num) {
      time = DateTime.fromMillisecondsSinceEpoch(ts.toInt());
    } else {
      time = DateTime.tryParse('${iso ?? ''}')?.toLocal() ?? DateTime.now();
    }
    int? asInt(Object? value) => value is num ? value.toInt() : int.tryParse('${value ?? ''}');
    String? asText(Object? value) {
      final text = '${value ?? ''}'.trim();
      return text.isEmpty ? null : text;
    }

    return GatewayEventEntry(
      time: time,
      event: asText(raw['event']) ?? 'unknown',
      code: asInt(raw['code']),
      codeSource: asText(raw['codeSource']),
      codeName: asText(raw['codeName']),
      codeText: asText(raw['codeText']),
      reason: asText(raw['reason']),
      uptimeMs: asInt(raw['uptimeMs']),
      sinceLastReadyMs: asInt(raw['sinceLastReadyMs']),
      attempt: asInt(raw['attempt']),
      message: asText(raw['message']) ?? asText(raw['detail']),
      raw: raw.map((key, value) => MapEntry('$key', value)),
    );
  }
}

/// 一次读取的结果：文件位置、总行数和事件列表。
class GatewayEventLog {
  const GatewayEventLog({required this.path, required this.lines, required this.events});

  const GatewayEventLog.empty() : path = '', lines = 0, events = const [];

  /// 实际读取的文件路径；为空说明 Runtime 还没产生过任何网关事件。
  final String path;

  /// 文件总行数（可能大于 [events] 的长度，因为只取尾部）。
  final int lines;

  final List<GatewayEventEntry> events;

  bool get isEmpty => events.isEmpty;

  factory GatewayEventLog.fromMap(Map raw) {
    final events = (raw['events'] as List? ?? const [])
        .whereType<Map>()
        .map(GatewayEventEntry.fromMap)
        .toList();
    return GatewayEventLog(
      path: '${raw['path'] ?? ''}',
      lines: (raw['lines'] as num?)?.toInt() ?? events.length,
      events: events,
    );
  }
}
