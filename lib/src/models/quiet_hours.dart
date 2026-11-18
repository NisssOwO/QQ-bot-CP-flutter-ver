import 'dart:convert';

/// 一个静默时间段，用「当天第几分钟」表示，方便跨夜比较。
/// 23:00–08:00 存成 1380→480：结束小于等于开始时表示跨夜。
class QuietWindow {
  const QuietWindow(this.startMinutes, this.endMinutes);

  final int startMinutes, endMinutes;

  static const _minutesPerDay = 24 * 60;

  static String formatMinutes(int minutes) {
    final value = minutes.clamp(0, _minutesPerDay);
    final hour = value ~/ 60;
    final minute = value % 60;
    return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  }

  /// "23:00" → 1380；非法输入返回 null（Node 端同样只接受这种形式）。
  static int? parseMinutes(String? text) {
    final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch((text ?? '').trim());
    if (match == null) return null;
    final hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    if (hour > 23 || minute > 59) return null;
    return hour * 60 + minute;
  }

  String get startLabel => formatMinutes(startMinutes);
  String get endLabel => formatMinutes(endMinutes);
  String get label => '$startLabel–$endLabel';

  /// 只写了 23:00–08:00 这种跨夜段才是 true（雷同的结束时间视为非法而非跨夜）。
  bool get crossesMidnight => endMinutes < startMinutes;

  /// 起止相同视为无效配置，Node 端会直接跳过；界面也不该允许保存。
  bool get isValid => startMinutes != endMinutes;

  bool contains(int minutes) => crossesMidnight
      ? minutes >= startMinutes || minutes < endMinutes
      : minutes >= startMinutes && minutes < endMinutes;

  static QuietWindow? tryParse(Object? raw) {
    if (raw is List && raw.length >= 2) {
      final start = parseMinutes('${raw[0]}');
      final end = parseMinutes('${raw[1]}');
      if (start == null || end == null) return null;
      return QuietWindow(start, end);
    }
    if (raw is Map) {
      final start = parseMinutes('${raw['start']}');
      final end = parseMinutes('${raw['end']}');
      if (start == null || end == null) return null;
      return QuietWindow(start, end);
    }
    return null;
  }

  List<String> toJson() => [startLabel, endLabel];

  static List<QuietWindow> tryParseList(Object? raw) {
    if (raw is! List) return const [];
    final list = <QuietWindow>[];
    for (final item in raw) {
      final window = tryParse(item);
      if (window != null) list.add(window);
    }
    list.sort((a, b) => a.startMinutes.compareTo(b.startMinutes));
    return list;
  }

  @override
  bool operator ==(Object other) =>
      other is QuietWindow &&
      other.startMinutes == startMinutes &&
      other.endMinutes == endMinutes;

  @override
  int get hashCode => Object.hash(startMinutes, endMinutes);

  @override
  String toString() => label;
}

/// 静默时间配置。工作时段和周末/节假日各有一套窗口，按「今天算不算工作日」二选一；
/// 某一套留空表示那一天不静默。
class QuietHoursSettings {
  const QuietHoursSettings({
    this.enabled = true,
    this.holidays = 'cn',
    this.workdays = const [1, 2, 3, 4, 5],
    this.workdayWindows = const [QuietWindow(23 * 60, 8 * 60)],
    this.offdayWindows = const [QuietWindow(23 * 60, 9 * 60)],
  });

  /// 是否启用静默。关闭后只影响主动插话：主动回复不再因时间被拦。
  final bool enabled;

  /// 'cn' = 自动识别中国法定节假日与调休；'none' = 只按星期几判断。
  final String holidays;

  /// 哪几天算工作日（1=周一 … 7=周日），与法定节假日叠加判断。
  final List<int> workdays;

  final List<QuietWindow> workdayWindows, offdayWindows;

  bool get holidaysEnabled => holidays != 'none';

  QuietHoursSettings copyWith({
    bool? enabled,
    String? holidays,
    List<int>? workdays,
    List<QuietWindow>? workdayWindows,
    List<QuietWindow>? offdayWindows,
  }) =>
      QuietHoursSettings(
        enabled: enabled ?? this.enabled,
        holidays: holidays ?? this.holidays,
        workdays: workdays ?? this.workdays,
        workdayWindows: workdayWindows ?? this.workdayWindows,
        offdayWindows: offdayWindows ?? this.offdayWindows,
      );

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'holidays': holidays,
        'workday': {
          'weekdays': workdays,
          'windows': [for (final w in workdayWindows) w.toJson()],
        },
        'offday': {
          'windows': [for (final w in offdayWindows) w.toJson()],
        },
      };

  factory QuietHoursSettings.fromJson(Map raw) {
    final workday = raw['workday'] is Map ? raw['workday'] as Map : const {};
    final offday = raw['offday'] is Map ? raw['offday'] as Map : const {};
    final weekdaysRaw = workday['weekdays'];
    final workdays = weekdaysRaw is List
        ? {
            for (final item in weekdaysRaw)
              if (item is num && item >= 1 && item <= 7) item.toInt()
          }.toList()
        : const [1, 2, 3, 4, 5];
    return QuietHoursSettings(
      enabled: raw['enabled'] != false,
      holidays: '${raw['holidays'] ?? 'cn'}' == 'none' ? 'none' : 'cn',
      workdays: workdays.isEmpty ? const [1, 2, 3, 4, 5] : workdays,
      workdayWindows: workday.containsKey('windows')
          ? QuietWindow.tryParseList(workday['windows'])
          : const [QuietWindow(23 * 60, 8 * 60)],
      offdayWindows: offday.containsKey('windows')
          ? QuietWindow.tryParseList(offday['windows'])
          : const [QuietWindow(23 * 60, 9 * 60)],
    );
  }

  /// '工作日 23:00–08:00、23:00–09:00' 这种一行摘要，给卡片副标题用。
  String get summary {
    final parts = <String>[];
    if (workdayWindows.isNotEmpty) {
      parts.add('工作日 ${workdayWindows.map((w) => w.label).join('、')}');
    }
    if (offdayWindows.isNotEmpty) {
      parts.add('周末 ${offdayWindows.map((w) => w.label).join('、')}');
    }
    return parts.isEmpty ? '未设置静默时段' : parts.join(' · ');
  }
}

/// 配置文件本身（`.dsh-qqbot/quiet-hours.json`）。顶层直接铺开设置字段，
/// 与 Node 端读取的结构保持一致，避免多一层嵌套。
class QuietHoursConfig {
  const QuietHoursConfig({this.schemaVersion = 1, this.settings = const QuietHoursSettings()});

  final int schemaVersion;
  final QuietHoursSettings settings;

  QuietHoursConfig withSettings(QuietHoursSettings value) =>
      QuietHoursConfig(schemaVersion: schemaVersion, settings: value);

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        ...settings.toJson(),
      };

  String encode() => jsonEncode(toJson());

  factory QuietHoursConfig.fromJson(Map raw) => QuietHoursConfig(
        schemaVersion: raw['schemaVersion'] is num ? (raw['schemaVersion'] as num).toInt() : 1,
        settings: QuietHoursSettings.fromJson(raw),
      );
}

/// Node 侧写入的临时覆盖（`.dsh-qqbot/quiet-hours-override.json`）。
class QuietHoursOverride {
  const QuietHoursOverride({this.kind = '', this.until});

  /// 'minutes' | 'window' | 'day'；空串表示没有覆盖。
  final String kind;
  final DateTime? until;

  bool get active => until != null && until!.isAfter(DateTime.now());

  String get kindLabel => switch (kind) {
        'minutes' => '15 分钟',
        'window' => '跳过一个窗口',
        'day' => '今天不再静默',
        _ => '临时覆盖',
      };

  static DateTime? _time(Object? value) =>
      value is num && value > 0 ? DateTime.fromMillisecondsSinceEpoch(value.toInt()) : null;

  factory QuietHoursOverride.fromJson(Object? raw) {
    if (raw is! Map) return const QuietHoursOverride();
    return QuietHoursOverride(
      kind: '${raw['kind'] ?? ''}',
      until: _time(raw['until']),
    );
  }
}

/// Node 侧写的状态快照（`.dsh-qqbot/quiet-hours-state.json`），
/// 与参考项目 QuietHours.status() 的字段名保持一致。
class QuietHoursStatus {
  const QuietHoursStatus({
    this.loaded = false,
    this.enabled = true,
    this.state = 'normal',
    this.dayKind = 'workday',
    this.windowLabel = '',
    this.until,
    this.holidayName = '',
    this.override = const QuietHoursOverride(),
    this.localTime = '',
    this.date = '',
    this.suppressed = 0,
  });

  /// 状态文件存在且由 Node 写过（运行时至少启动过一次新版）。
  final bool loaded;
  final bool enabled;

  /// 'normal' | 'quiet' | 'override'
  final String state;

  /// 'workday' | 'offday'
  final String dayKind;
  final String windowLabel;
  final DateTime? until;
  final String holidayName;
  final QuietHoursOverride override;
  final String localTime, date;

  /// 被静默挡下的主动插话次数（含冷却重置前累计）。
  final int suppressed;

  bool get isQuiet => state == 'quiet';
  bool get isOverride => state == 'override';

  bool get isWorkday => dayKind == 'workday';

  /// '工作日' / '周末' / '法定节假日：<名称>'
  String get dayLabel {
    if (holidayName.isNotEmpty) return '法定节假日：$holidayName';
    return isWorkday ? '工作日' : '周末';
  }

  String get stateLabel => switch (state) {
        'quiet' => '静默中',
        'override' => '临时覆盖',
        _ => '正常',
      };

  /// '到 08:00' 这种尾注；没有结束时间返回空串。
  String get untilLabel {
    final time = until;
    if (time == null) return '';
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '到 $hour:$minute';
  }

  static DateTime? _time(Object? value) =>
      value is num && value > 0 ? DateTime.fromMillisecondsSinceEpoch(value.toInt()) : null;

  factory QuietHoursStatus.fromJson(Map raw) => QuietHoursStatus(
        loaded: raw['schemaVersion'] != null,
        enabled: raw['enabled'] != false,
        state: '${raw['state'] ?? 'normal'}',
        dayKind: '${raw['dayKind'] ?? 'workday'}' == 'offday' ? 'offday' : 'workday',
        windowLabel: '${raw['window'] ?? ''}',
        until: _time(raw['until']),
        holidayName: '${raw['holiday'] ?? ''}',
        override: QuietHoursOverride.fromJson(raw['override']),
        localTime: '${raw['localTime'] ?? ''}',
        date: '${raw['date'] ?? ''}',
        suppressed: raw['suppressed'] is num ? (raw['suppressed'] as num).toInt() : 0,
      );
}
