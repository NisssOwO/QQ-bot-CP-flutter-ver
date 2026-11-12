import 'dart:convert';

/// 数字设置项的取值范围，与 Node 端 `proactive-reply.js` 的 clamp 表保持一致。
class ProactiveReplyRange {
  const ProactiveReplyRange(this.min, this.max);
  final int min, max;
  int clamp(int value) => value < min ? min : (value > max ? max : value);
}

const proactiveReplyRanges = <String, ProactiveReplyRange>{
  'probability': ProactiveReplyRange(0, 100),
  'minMessages': ProactiveReplyRange(1, 100),
  'cooldownSeconds': ProactiveReplyRange(0, 86400),
  'dailyLimitPerGroup': ProactiveReplyRange(0, 1000),
  'historyMessages': ProactiveReplyRange(1, 100),
  'minTextLength': ProactiveReplyRange(1, 5000),
  'maxTextLength': ProactiveReplyRange(1, 5000),
  'requireRecentActivitySeconds': ProactiveReplyRange(0, 86400),
};

class ProactiveReplySettings {
  const ProactiveReplySettings({
    this.enabled = false,
    this.probability = 5,
    this.minMessages = 3,
    this.cooldownSeconds = 300,
    this.dailyLimitPerGroup = 20,
    this.historyMessages = 12,
    this.minTextLength = 2,
    this.maxTextLength = 500,
    this.requireRecentActivitySeconds = 900,
    this.quietHoursEnabled = true,
    this.quietStart = '23:00',
    this.quietEnd = '08:00',
  });
  final bool enabled;
  final int probability,
      minMessages,
      cooldownSeconds,
      dailyLimitPerGroup,
      historyMessages,
      minTextLength,
      maxTextLength,
      requireRecentActivitySeconds;
  final bool quietHoursEnabled;
  final String quietStart, quietEnd;

  /// 用一个 JSON 字段名修改设置；未知字段原样返回。
  ProactiveReplySettings withValue(String key, Object value) =>
      ProactiveReplySettings.fromJson({...toJson(), key: value});

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'probability': probability,
        'minMessages': minMessages,
        'cooldownSeconds': cooldownSeconds,
        'dailyLimitPerGroup': dailyLimitPerGroup,
        'historyMessages': historyMessages,
        'minTextLength': minTextLength,
        'maxTextLength': maxTextLength,
        'requireRecentActivitySeconds': requireRecentActivitySeconds,
        'quietHoursEnabled': quietHoursEnabled,
        'quietStart': quietStart,
        'quietEnd': quietEnd,
      };

  factory ProactiveReplySettings.fromJson(Map raw) {
    int read(String key, int fallback) {
      final value = raw[key];
      final range = proactiveReplyRanges[key]!;
      return value is num ? range.clamp(value.toInt()) : fallback;
    }

    final minText = read('minTextLength', 2);
    final maxText = read('maxTextLength', 500);
    return ProactiveReplySettings(
        enabled: raw['enabled'] == true,
        probability: read('probability', 5),
        minMessages: read('minMessages', 3),
        cooldownSeconds: read('cooldownSeconds', 300),
        dailyLimitPerGroup: read('dailyLimitPerGroup', 20),
        historyMessages: read('historyMessages', 12),
        minTextLength: minText > maxText ? maxText : minText,
        maxTextLength: maxText,
        requireRecentActivitySeconds: read('requireRecentActivitySeconds', 900),
        quietHoursEnabled: raw['quietHoursEnabled'] != false,
        quietStart: '${raw['quietStart'] ?? '23:00'}',
        quietEnd: '${raw['quietEnd'] ?? '08:00'}');
  }
}

/// 全局设置 + 群级差量覆盖。群配置只保存与全局不同的字段，
/// 读取时与全局合并，因此修改全局会同步到没有单独改过该字段的群。
class ProactiveReplyConfig {
  const ProactiveReplyConfig(
      {this.schemaVersion = 1,
      this.global = const ProactiveReplySettings(),
      this.groups = const {}});
  final int schemaVersion;
  final ProactiveReplySettings global;
  final Map<String, Map<String, dynamic>> groups;

  ProactiveReplySettings effective(String group) => group.isEmpty
      ? global
      : ProactiveReplySettings.fromJson(
          {...global.toJson(), ...?groups[group]});

  /// 保存某个群的设置，只记录与全局不同的字段；没有差异时删除覆盖。
  ProactiveReplyConfig withGroup(String group, ProactiveReplySettings value) {
    final base = global.toJson();
    final diff = <String, dynamic>{
      for (final e in value.toJson().entries)
        if (base[e.key] != e.value) e.key: e.value
    };
    final next = Map<String, Map<String, dynamic>>.from(groups);
    if (diff.isEmpty) {
      next.remove(group);
    } else {
      next[group] = diff;
    }
    return ProactiveReplyConfig(global: global, groups: next);
  }

  ProactiveReplyConfig withoutGroup(String group) => ProactiveReplyConfig(
      global: global, groups: Map.of(groups)..remove(group));

  ProactiveReplyConfig withGlobal(ProactiveReplySettings value) =>
      ProactiveReplyConfig(global: value, groups: groups);

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'global': global.toJson(),
        'groups': groups
      };
  String encode() => jsonEncode(toJson());

  factory ProactiveReplyConfig.fromJson(Map raw) {
    final global =
        ProactiveReplySettings.fromJson((raw['global'] as Map?) ?? const {});
    final base = global.toJson();
    final groups = <String, Map<String, dynamic>>{};
    ((raw['groups'] as Map?) ?? const {}).forEach((key, value) {
      if (value is! Map) return;
      // 兼容旧版完整拷贝：只保留与全局不同、且是已知字段的值。
      final diff = <String, dynamic>{
        for (final e in value.entries)
          if (base.containsKey('${e.key}') && base['${e.key}'] != e.value)
            '${e.key}': e.value
      };
      if (diff.isNotEmpty) groups['$key'] = diff;
    });
    return ProactiveReplyConfig(
        schemaVersion: raw['schemaVersion'] is num
            ? (raw['schemaVersion'] as num).toInt()
            : 1,
        global: global,
        groups: groups);
  }
}

/// Node 端写入的运行状态（`proactive-reply-state.json`）。
class ProactiveReplyGroupStatus {
  const ProactiveReplyGroupStatus(
      {required this.groupId,
      this.today = 0,
      this.lastReply,
      this.lastSeen,
      this.lastSender = '',
      this.lastText = '',
      this.lastAttempt,
      this.lastResult = '',
      this.sinceReply = 0,
      this.lastTest,
      this.lastTestId = '',
      this.lastTestResult = ''});
  final String groupId;
  final int today, sinceReply;
  final DateTime? lastReply, lastSeen, lastAttempt, lastTest;
  final String lastSender, lastText, lastResult, lastTestId, lastTestResult;

  static DateTime? _time(Object? v) => v is num && v > 0
      ? DateTime.fromMillisecondsSinceEpoch(v.toInt())
      : null;

  factory ProactiveReplyGroupStatus.fromJson(String id, Map raw,
      {DateTime? now}) {
    final current = now ?? DateTime.now();
    final day = '${current.year}-${current.month}-${current.day}';
    return ProactiveReplyGroupStatus(
        groupId: id,
        today: raw['day'] == day && raw['count'] is num
            ? (raw['count'] as num).toInt()
            : 0,
        lastReply: _time(raw['lastReply']),
        lastSeen: _time(raw['lastSeen']),
        lastSender: '${raw['lastSender'] ?? ''}',
        lastText: '${raw['lastText'] ?? ''}',
        lastAttempt: _time(raw['lastAttempt']),
        lastResult: '${raw['lastResult'] ?? ''}',
        sinceReply:
            raw['sinceReply'] is num ? (raw['sinceReply'] as num).toInt() : 0,
        lastTest: _time(raw['lastTest']),
        lastTestId: '${raw['lastTestId'] ?? ''}',
        lastTestResult: '${raw['lastTestResult'] ?? ''}');
  }

  static List<ProactiveReplyGroupStatus> listFromJson(Map raw,
      {DateTime? now}) {
    final groups = (raw['groups'] as Map?) ?? const {};
    final list = [
      for (final e in groups.entries)
        if (e.value is Map)
          ProactiveReplyGroupStatus.fromJson('${e.key}', e.value as Map,
              now: now)
    ];
    list.sort((a, b) => (b.lastSeen ?? DateTime(0))
        .compareTo(a.lastSeen ?? DateTime(0)));
    return list;
  }
}

/// 状态文件的顶层信息：Node 是否在观察群消息、实际使用的时区，以及各群状态。
class ProactiveReplyRuntimeStatus {
  const ProactiveReplyRuntimeStatus(
      {this.loaded = false,
      this.requireMention = true,
      this.timeZone = '',
      this.utcOffsetMinutes,
      this.groups = const []});

  /// 状态文件存在且由 Node 写过（Runtime 至少启动过一次新版主动回复）。
  final bool loaded;

  /// 群聊必须 @ 才回复。为 false 时 Node 不观察未 @ 消息，主动回复不工作。
  final bool requireMention;
  final String timeZone;
  final int? utcOffsetMinutes;
  final List<ProactiveReplyGroupStatus> groups;

  ProactiveReplyGroupStatus? group(String id) {
    for (final g in groups) {
      if (g.groupId == id) return g;
    }
    return null;
  }

  /// Node 时区偏移与手机不一致时返回 true（安静时段会按 Node 时区算）。
  bool timeZoneMismatch(DateTime now) =>
      utcOffsetMinutes != null &&
      utcOffsetMinutes != now.timeZoneOffset.inMinutes;

  String get timeZoneLabel {
    final offset = utcOffsetMinutes;
    if (offset == null) return timeZone.isEmpty ? '未知' : timeZone;
    final sign = offset < 0 ? '-' : '+';
    final abs = offset.abs();
    final hh = (abs ~/ 60).toString().padLeft(2, '0');
    final mm = (abs % 60).toString().padLeft(2, '0');
    final zone = timeZone.isEmpty ? '' : '$timeZone ';
    return '${zone}UTC$sign$hh:$mm';
  }

  factory ProactiveReplyRuntimeStatus.fromJson(Map raw, {DateTime? now}) =>
      ProactiveReplyRuntimeStatus(
          loaded: raw['schemaVersion'] != null,
          requireMention: raw['requireMention'] != false,
          timeZone: '${raw['timeZone'] ?? ''}',
          utcOffsetMinutes: raw['utcOffsetMinutes'] is num
              ? (raw['utcOffsetMinutes'] as num).toInt()
              : null,
          groups: ProactiveReplyGroupStatus.listFromJson(raw, now: now));
}
