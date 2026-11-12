/// QQ 网关（WebSocket 长连接）的真实状态。
///
/// 进程活着不等于在线：中间件注册失败、凭据被拒、SDK 放弃重连都会留下
/// “App 正常、QQ 显示离线”的静默故障。Node 侧把 SDK 事件（ready /
/// disconnected / start 失败）写进 `filesDir/.dsh-qqbot/gateway-status.json`
/// 并每 20 秒刷心跳，这里只负责解析与派生展示文案。
enum GatewayState {
  online,
  connecting,
  reconnecting,
  offline,
  failed,
  unknown;

  static GatewayState parse(String raw) => switch (raw) {
        'online' => GatewayState.online,
        'connecting' => GatewayState.connecting,
        'reconnecting' => GatewayState.reconnecting,
        'offline' => GatewayState.offline,
        'failed' => GatewayState.failed,
        _ => GatewayState.unknown,
      };

  /// 是否处于“应该收到消息”的正常状态。
  bool get isUp => this == GatewayState.online;

  /// 需要用户注意的状态（离线、启动失败）。
  bool get isBad => this == GatewayState.offline || this == GatewayState.failed;
}

class GatewayStatus {
  const GatewayStatus({
    this.state = 'unknown',
    this.appId = '',
    this.since = 0,
    this.updatedAt = 0,
    this.attempts = 0,
    this.code,
    this.reason = '',
    this.error = '',
    this.lastError = '',
  });

  final String state;
  final String appId;

  /// 本次进入 online 的起始时间（毫秒）。
  final int since;

  /// 最后一次心跳写入时间（毫秒）；只有在线时才会更新。
  final int updatedAt;
  final int attempts;
  final int? code;
  final String reason;
  final String error;
  final String lastError;

  GatewayState get kind => GatewayState.parse(state);

  /// 心跳超过这个时长没更新，说明网关那条连接已经没人维护了。
  static const Duration staleAfter = Duration(seconds: 90);

  bool get hasData => state != 'unknown' && updatedAt > 0;

  DateTime? get updated => updatedAt > 0 ? DateTime.fromMillisecondsSinceEpoch(updatedAt) : null;

  DateTime? get sinceAt => since > 0 ? DateTime.fromMillisecondsSinceEpoch(since) : null;

  /// 在线但心跳停了：进程还在、连接已经不动了，这是最容易被忽略的故障。
  bool heartbeatStale(DateTime now) {
    final at = updated;
    if (at == null || kind != GatewayState.online) return false;
    return now.difference(at) > staleAfter;
  }

  /// 已连接时长（只在在线且心跳新鲜时有意义）。
  Duration? connectedFor(DateTime now) {
    final at = sinceAt;
    if (at == null || kind != GatewayState.online || heartbeatStale(now)) return null;
    final span = now.difference(at);
    return span.isNegative ? null : span;
  }

  factory GatewayStatus.fromMap(Map<dynamic, dynamic> raw) {
    int asInt(Object? value, [int fallback = 0]) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value) ?? fallback;
      return fallback;
    }

    String asString(Object? value) => value == null ? '' : '$value';

    return GatewayStatus(
      state: asString(raw['state']).isEmpty ? 'unknown' : asString(raw['state']),
      appId: asString(raw['appId']),
      since: asInt(raw['since']),
      updatedAt: asInt(raw['updatedAt']),
      attempts: asInt(raw['attempts']),
      code: raw['code'] == null ? null : asInt(raw['code']),
      reason: asString(raw['reason']),
      error: asString(raw['error']),
      lastError: asString(raw['lastError']),
    );
  }
}