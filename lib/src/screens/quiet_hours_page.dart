import 'package:flutter/material.dart';

import '../models/quiet_hours.dart';
import '../services/runtime_bridge.dart';
import '../theme/app_theme.dart';
import '../theme/app_theme_tokens.dart';

/// 「静默时间」：控制机器人什么时候不主动插话。
/// 静默只拦主动回复这条路径，@ 与私聊走的是另一条逻辑，不受影响。
class QuietHoursPage extends StatefulWidget {
  const QuietHoursPage({super.key, required this.bridge});

  final RuntimeBridge bridge;

  @override
  State<QuietHoursPage> createState() => _QuietHoursPageState();
}

class _QuietHoursPageState extends State<QuietHoursPage> {
  static const _weekdayLabels = <String>['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

  QuietHoursConfig? _config;
  QuietHoursStatus _status = const QuietHoursStatus();
  QuietHoursSettings _draft = const QuietHoursSettings();
  bool _saving = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// 状态读不到不影响编辑配置：页面其余部分照常可用。
  Future<QuietHoursStatus> _readStatus() async {
    try {
      return await widget.bridge.quietHoursStatus();
    } catch (_) {
      return const QuietHoursStatus();
    }
  }

  Future<void> _load({bool resetDraft = true}) async {
    try {
      // 两个请求并行发出：状态卡不该等配置读完才出现。
      final configFuture = widget.bridge.quietHoursConfig();
      final status = await _readStatus();
      final config = await configFuture;
      if (!mounted) return;
      setState(() {
        _config = config;
        _status = status;
        _loadError = null;
        if (resetDraft) _draft = config.settings;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadError = '$e');
      _toast('读取静默时间配置失败：$e');
    }
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  static String _hhmm(DateTime? value) =>
      value == null ? '—' : '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

  String _dayLabel(QuietHoursStatus status) {
    if (status.holidayName.isNotEmpty) return '法定节假日：${status.holidayName}';
    return status.dayKind == 'workday' ? '工作日' : '周末';
  }

  String _remaining(DateTime? until) {
    if (until == null) return '';
    final rest = until.difference(DateTime.now());
    if (rest.isNegative) return '';
    return rest.inMinutes < 1 ? '（剩余不到 1 分钟）' : '（剩余 ${rest.inMinutes} 分钟）';
  }

  void _toggleWorkday(int day) {
    final next = [..._draft.workdays];
    if (!next.remove(day)) next.add(day);
    next.sort();
    setState(() => _draft = _draft.copyWith(workdays: next));
  }

  Future<void> _addWindow({required bool workday}) async {
    final start = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 23, minute: 0),
      helpText: '静默开始',
    );
    if (start == null || !mounted) return;
    final end = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 8, minute: 0),
      helpText: '静默结束',
    );
    if (end == null || !mounted) return;
    final startMinutes = start.hour * 60 + start.minute;
    final endMinutes = end.hour * 60 + end.minute;
    if (startMinutes == endMinutes) {
      _toast('开始和结束不能相同');
      return;
    }
    final window = QuietWindow(startMinutes, endMinutes);
    setState(() {
      _draft = workday
          ? _draft.copyWith(workdayWindows: [..._draft.workdayWindows, window])
          : _draft.copyWith(offdayWindows: [..._draft.offdayWindows, window]);
    });
  }

  void _removeWindow({required bool workday, required int index}) {
    final windows = [...(workday ? _draft.workdayWindows : _draft.offdayWindows)]..removeAt(index);
    setState(() {
      _draft = workday
          ? _draft.copyWith(workdayWindows: windows)
          : _draft.copyWith(offdayWindows: windows);
    });
  }

  Future<void> _setOverride(String kind) async {
    try {
      await widget.bridge.setQuietHoursOverride(kind);
      // 覆盖只改变运行状态，不动配置；保留用户正在编辑的草稿。
      await _load(resetDraft: false);
      _toast('已设置临时覆盖');
      await _reloadAfterRuntimeTick(expectOverride: true);
    } catch (e) {
      _toast('设置临时覆盖失败：$e');
    }
  }

  Future<void> _clearOverride() async {
    try {
      await widget.bridge.clearQuietHoursOverride();
      await _load(resetDraft: false);
      _toast('已取消临时覆盖');
      await _reloadAfterRuntimeTick(expectOverride: false);
    } catch (e) {
      _toast('取消临时覆盖失败：$e');
    }
  }

  /// 覆盖是 Kotlin 写文件、Node 每 5 秒把判定结果写回状态快照，
  /// 所以刚点完再读一次拿到的还是旧状态。等一轮 tick 之后再读，
  /// 界面才会从"三个按钮"切到"覆盖中 · 到 HH:mm"。
  Future<void> _reloadAfterRuntimeTick({required bool expectOverride}) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      await Future<void>.delayed(const Duration(seconds: 2));
      if (!mounted) return;
      await _load(resetDraft: false);
      if (_status.isOverride == expectOverride) return;
    }
  }

  Future<void> _save() async {
    final config = _config;
    if (config == null || _saving) return;
    setState(() => _saving = true);
    try {
      final next = config.withSettings(_draft);
      await widget.bridge.saveQuietHoursConfig(next);
      if (!mounted) return;
      setState(() => _config = next);
      await _load(resetDraft: false);
      _toast('已保存，运行中的机器人约 2 秒内生效');
    } catch (e) {
      _toast('保存失败：$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppSurfaceTokens.of(context);
    final config = _config;
    return Scaffold(
      appBar: AppBar(
        title: const Text('静默时间'),
        actions: [
          if (config != null)
            TextButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? '保存中…' : '保存'),
            ),
        ],
      ),
      body: config == null
          ? _placeholder(tokens)
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  _statusCard(tokens),
                  const SizedBox(height: 8),
                  Text(
                    '静默只影响主动插话。被 @ 和私聊消息照常回复，不受影响。',
                    style: TextStyle(fontSize: 12.5, color: tokens.mutedText),
                  ),
                  const SizedBox(height: 12),
                  _enabledCard(),
                  const SizedBox(height: 12),
                  _workdayCard(tokens),
                  const SizedBox(height: 12),
                  _offdayCard(tokens),
                  const SizedBox(height: 12),
                  _holidayCard(tokens),
                  const SizedBox(height: 12),
                  _overrideCard(tokens),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _saving ? null : _save,
                      child: Text(_saving ? '保存中…' : '保存'),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  /// 配置没读到时不要给出一套假的默认值：那会让用户以为能保存。
  Widget _placeholder(AppSurfaceTokens tokens) {
    if (_loadError == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.cloud_off, color: tokens.mutedText),
          const SizedBox(height: 10),
          const Text('尚未与运行时通信'),
          const SizedBox(height: 4),
          Text(_loadError!, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: tokens.mutedText)),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('重试'),
          ),
        ]),
      ),
    );
  }

  Widget _statusCard(AppSurfaceTokens tokens) {
    final status = _status;
    final theme = AppThemeTokens.of(context);
    final tone = status.isOverride
        ? theme.warning
        : status.isQuiet
            ? tokens.heroEnd
            : theme.success;
    return AppCard(
      title: '当前状态',
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 9, height: 9, decoration: BoxDecoration(color: tone, shape: BoxShape.circle)),
        const SizedBox(width: 7),
        Text(
          status.loaded ? status.stateLabel : '未知',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: tone),
        ),
      ]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (!status.loaded)
          Text('尚未与运行时通信', style: TextStyle(fontSize: 13, color: tokens.mutedText))
        else ...[
          Text('今日：${_dayLabel(status)}', style: const TextStyle(fontSize: 13.5)),
          const SizedBox(height: 4),
          Text(
            status.windowLabel.isEmpty ? '当前不在静默时段' : '当前窗口 ${status.windowLabel}',
            style: TextStyle(fontSize: 13, color: tokens.mutedText),
          ),
          if (status.until != null)
            Text(
              '${status.isQuiet ? '静默到' : '持续到'} ${_hhmm(status.until)}',
              style: TextStyle(fontSize: 13, color: tokens.mutedText),
            ),
          if (status.isOverride)
            Text(
              '覆盖中 · 到 ${_hhmm(status.until)}${_remaining(status.until)}',
              style: TextStyle(fontSize: 13, color: theme.warning),
            ),
        ],
      ]),
    );
  }

  Widget _enabledCard() => AppCard(
        child: SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('启用静默'),
          subtitle: const Text('关闭后所有时间段都不生效'),
          value: _draft.enabled,
          onChanged: (value) => setState(() => _draft = _draft.copyWith(enabled: value)),
        ),
      );

  Widget _workdayCard(AppSurfaceTokens tokens) => AppCard(
        title: '工作日',
        subtitle: '只影响选中星期的静默时间段；跨夜的时间段会延续到第二天。',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 8, runSpacing: 4, children: [
            for (var i = 0; i < _weekdayLabels.length; i++)
              FilterChip(
                label: Text(_weekdayLabels[i]),
                selected: _draft.workdays.contains(i + 1),
                onSelected: (_) => _toggleWorkday(i + 1),
              ),
          ]),
          const SizedBox(height: 8),
          ..._windowRows(_draft.workdayWindows, tokens, workday: true),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _addWindow(workday: true),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('添加时间段'),
            ),
          ),
        ]),
      );

  Widget _offdayCard(AppSurfaceTokens tokens) => AppCard(
        title: '周末与法定节假日',
        subtitle: '周末与法定节假日使用这些时间段，不区分星期。',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ..._windowRows(_draft.offdayWindows, tokens, workday: false),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _addWindow(workday: false),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('添加时间段'),
            ),
          ),
        ]),
      );

  Widget _holidayCard(AppSurfaceTokens tokens) => AppCard(
        title: '节假日识别',
        child: SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('自动识别中国法定节假日'),
          subtitle: const Text('开启后自动识别中国法定节假日与调休补班，启动时拉取一次，失败时按星期判断。'),
          value: _draft.holidays == 'cn',
          onChanged: (value) => setState(() => _draft = _draft.copyWith(holidays: value ? 'cn' : 'none')),
        ),
      );

  Widget _overrideCard(AppSurfaceTokens tokens) {
    final status = _status;
    final active = status.isOverride;
    return AppCard(
      title: '临时覆盖',
      child: active
          ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('覆盖中 · 到 ${_hhmm(status.until)}', style: const TextStyle(fontSize: 13.5)),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _clearOverride,
                  icon: const Icon(Icons.close, size: 18),
                  label: const Text('取消覆盖'),
                ),
              ),
            ])
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                '临时打破或进入静默，不必修改上面的时间段。',
                style: TextStyle(fontSize: 12.5, color: tokens.mutedText),
              ),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                OutlinedButton(onPressed: () => _setOverride('minutes'), child: const Text('15 分钟')),
                OutlinedButton(onPressed: () => _setOverride('window'), child: const Text('跳过一个窗口')),
                OutlinedButton(onPressed: () => _setOverride('day'), child: const Text('今天不再静默')),
              ]),
            ]),
    );
  }

  List<Widget> _windowRows(List<QuietWindow> windows, AppSurfaceTokens tokens, {required bool workday}) {
    if (windows.isEmpty) {
      return [
        Text(
          '没有时间段，不会静默。',
          style: TextStyle(fontSize: 12.5, color: tokens.mutedText),
        ),
      ];
    }
    return [
      for (var i = 0; i < windows.length; i++)
        Row(children: [
          const Icon(Icons.nightlight_round, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(windows[i].label, style: const TextStyle(fontSize: 14))),
          IconButton(
            tooltip: '删除',
            onPressed: () => _removeWindow(workday: workday, index: i),
            icon: const Icon(Icons.delete_outline, size: 20),
          ),
        ]),
    ];
  }
}
