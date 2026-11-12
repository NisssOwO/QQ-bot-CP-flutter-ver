import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/proactive_reply.dart';
import '../services/runtime_bridge.dart';

class ProactiveReplyPage extends StatefulWidget {
  const ProactiveReplyPage({super.key, required this.bridge});
  final RuntimeBridge bridge;
  @override
  State<ProactiveReplyPage> createState() => _ProactiveReplyPageState();
}

class _ProactiveReplyPageState extends State<ProactiveReplyPage> {
  static const _fields = <(String, String, String)>[
    ('probability', '抽样概率', '%'),
    ('minMessages', '触发前最少消息数', '条'),
    ('cooldownSeconds', '冷却时间', '秒'),
    ('dailyLimitPerGroup', '每日每群上限', '条'),
    ('historyMessages', '上下文消息数', '条'),
    ('requireRecentActivitySeconds', '最近活跃窗口（0 为不限制）', '秒'),
    ('minTextLength', '最短文本长度', '字'),
    ('maxTextLength', '最长文本长度', '字'),
  ];

  ProactiveReplyConfig? _config;
  ProactiveReplyRuntimeStatus _runtime = const ProactiveReplyRuntimeStatus();
  List<ProactiveReplyGroupStatus> get _status => _runtime.groups;
  String _group = '';
  ProactiveReplySettings? _draft;
  final _controllers = <String, TextEditingController>{};
  bool _saving = false;
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    for (final f in _fields) {
      _controllers[f.$1] = TextEditingController();
    }
    _load();
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  ProactiveReplySettings get _saved =>
      (_config ?? const ProactiveReplyConfig()).effective(_group);

  bool get _dirty =>
      _draft != null &&
      _draft!.toJson().toString() != _saved.toJson().toString();

  void _resetDraft() {
    final s = _saved;
    _draft = s;
    final json = s.toJson();
    for (final f in _fields) {
      _controllers[f.$1]!.text = '${json[f.$1]}';
    }
  }

  Future<void> _load() async {
    try {
      final value = await widget.bridge.proactiveReplyConfig();
      var runtime = const ProactiveReplyRuntimeStatus();
      try {
        runtime = await widget.bridge.proactiveReplyStatus();
      } catch (_) {
        // 状态只用于展示，读取失败不影响配置。
      }
      if (!mounted) return;
      setState(() {
        _config = value;
        _runtime = runtime;
        _resetDraft();
      });
    } catch (e) {
      _toast('读取主动回复配置失败：$e');
    }
  }

  void _toast(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('放弃未保存的修改？'),
                content: const Text('切换编辑对象会丢失当前未保存的修改。'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('取消')),
                  TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('放弃'))
                ]));
    return ok == true;
  }

  Future<void> _select(String group) async {
    if (group == _group || !await _confirmDiscard()) return;
    setState(() {
      _group = group;
      _resetDraft();
    });
  }

  Future<void> _addGroup() async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('添加群'),
                content: TextField(
                    controller: controller,
                    autofocus: true,
                    decoration: const InputDecoration(
                        labelText: '群 OpenID',
                        hintText: '一般无需手填，群里有人发言后会自动出现在列表中')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('取消')),
                  TextButton(
                      onPressed: () =>
                          Navigator.pop(context, controller.text.trim()),
                      child: const Text('确定'))
                ]));
    controller.dispose();
    if (value != null && value.isNotEmpty) await _select(value);
  }

  Future<void> _persist(ProactiveReplyConfig next, String message) async {
    setState(() => _saving = true);
    try {
      await widget.bridge.saveProactiveReplyConfig(next);
      if (!mounted) return;
      setState(() {
        _config = next;
        _resetDraft();
      });
      _toast(message);
    } catch (e) {
      _toast('保存失败：$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _save() async {
    final draft = _draft;
    if (draft == null) return;
    var json = draft.toJson();
    for (final f in _fields) {
      final range = proactiveReplyRanges[f.$1]!;
      final parsed = int.tryParse(_controllers[f.$1]!.text.trim());
      if (parsed == null || parsed < range.min || parsed > range.max) {
        _toast('${f.$2} 需在 ${range.min}–${range.max} 之间');
        return;
      }
      json[f.$1] = parsed;
    }
    if ((json['minTextLength'] as int) > (json['maxTextLength'] as int)) {
      _toast('最短文本长度不能大于最长文本长度');
      return;
    }
    final settings = ProactiveReplySettings.fromJson(json);
    final current = _config ?? const ProactiveReplyConfig();
    final next = _group.isEmpty
        ? current.withGlobal(settings)
        : current.withGroup(_group, settings);
    await _persist(next, '已保存，运行中的机器人约 2 秒内生效');
  }

  Future<void> _clearGroupOverride() async {
    final current = _config;
    if (current == null || _group.isEmpty) return;
    await _persist(current.withoutGroup(_group), '已清除群单独设置，改为跟随全局');
  }

  /// 写测试请求，然后最多等 75 秒（模型超时 60 秒 + 轮询）读结果。
  Future<void> _test() async {
    if (_group.isEmpty || _testing) return;
    setState(() => _testing = true);
    try {
      final id = await widget.bridge.testProactiveReply(_group);
      final deadline = DateTime.now().add(const Duration(seconds: 75));
      while (mounted && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(seconds: 2));
        final runtime = await widget.bridge.proactiveReplyStatus();
        final g = runtime.group(_group);
        if (g != null && g.lastTestId == id) {
          if (!mounted) return;
          setState(() => _runtime = runtime);
          _toast(g.lastTestResult);
          return;
        }
      }
      _toast('没等到结果：确认 Runtime 正在运行，且已安装新版运行时');
    } catch (e) {
      _toast('测试失败：$e');
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  String _ago(DateTime? t) {
    if (t == null) return '无';
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return '刚刚';
    if (d.inHours < 1) return '${d.inMinutes} 分钟前';
    if (d.inDays < 1) return '${d.inHours} 小时前';
    return '${d.inDays} 天前';
  }

  String _label(String id) {
    final s = _status.where((e) => e.groupId == id).firstOrNull;
    final short = id.length > 10 ? '${id.substring(0, 10)}…' : id;
    return s == null || s.lastText.isEmpty ? short : '$short（${s.lastSender}）';
  }

  @override
  Widget build(BuildContext context) {
    final config = _config;
    final draft = _draft;
    if (config == null || draft == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final ids = <String>{
      ..._status.map((e) => e.groupId),
      ...config.groups.keys,
      if (_group.isNotEmpty) _group
    }.toList();
    final current = _status.where((e) => e.groupId == _group).firstOrNull;
    final overridden = config.groups[_group]?.keys.toSet() ?? const <String>{};
    return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              Text('主动群聊', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 6),
              const Text('群里没人 @ 机器人时，按下面的规则偶尔插一句话。'
                  '使用和机器人相同的模型与角色卡；命中规则后才会调用模型。'),
              const SizedBox(height: 4),
              const Text('需要群主在 QQ 机器人设置中开启“获取群内全部消息”。'
                  '回复引用触发消息，5 分钟内未生成完成会放弃。',
                  style: TextStyle(color: Colors.grey)),
              if (_runtime.loaded && !_runtime.requireMention)
                Card(
                    color: Theme.of(context).colorScheme.errorContainer,
                    margin: const EdgeInsets.only(top: 12),
                    child: const ListTile(
                        leading: Icon(Icons.warning_amber),
                        title: Text('主动回复当前不会工作'),
                        subtitle: Text('机器人已设置为群里不 @ 也回复每条消息，'
                            '这时没有“插话”的概念。恢复“群聊必须 @”后此页设置才生效。'))),
              if (_runtime.loaded) ...[
                const SizedBox(height: 4),
                Text(
                    '安静时段按机器人时区 ${_runtime.timeZoneLabel} 计算'
                    '${_runtime.timeZoneMismatch(DateTime.now()) ? '（与手机时区不同，重启 Runtime 后会同步）' : ''}',
                    style: TextStyle(
                        fontSize: 12,
                        color: _runtime.timeZoneMismatch(DateTime.now())
                            ? Theme.of(context).colorScheme.error
                            : Colors.grey)),
              ],
              const SizedBox(height: 16),
              Text('编辑对象', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 6),
              Wrap(spacing: 8, runSpacing: 4, children: [
                ChoiceChip(
                    label: const Text('全局默认'),
                    selected: _group.isEmpty,
                    onSelected: (_) => _select('')),
                for (final id in ids)
                  ChoiceChip(
                      label: Text(_label(id) +
                          (config.groups.containsKey(id) ? ' *' : '')),
                      selected: _group == id,
                      onSelected: (_) => _select(id)),
                ActionChip(
                    avatar: const Icon(Icons.add, size: 18),
                    label: const Text('手动添加'),
                    onPressed: _addGroup),
              ]),
              const SizedBox(height: 4),
              const Text('带 * 的群有单独设置；没有单独设置的字段跟随全局。',
                  style: TextStyle(color: Colors.grey, fontSize: 12)),
              if (_group.isNotEmpty) _statusCard(current, overridden),
              const SizedBox(height: 8),
              Card(
                  child: Column(children: [
                SwitchListTile(
                    title: const Text('允许随机接话'),
                    subtitle: const Text('关闭后只保留普通 @ 回复'),
                    value: draft.enabled,
                    onChanged: (v) => setState(
                        () => _draft = draft.withValue('enabled', v))),
                for (final f in _fields) _numberField(f, overridden),
                SwitchListTile(
                    title: const Text('安静时段'),
                    subtitle: Text('${draft.quietStart} - ${draft.quietEnd}'),
                    value: draft.quietHoursEnabled,
                    onChanged: (v) => setState(() =>
                        _draft = draft.withValue('quietHoursEnabled', v))),
                ListTile(
                    title: const Text('安静时段开始'),
                    subtitle: Text(draft.quietStart),
                    trailing: const Icon(Icons.schedule),
                    onTap: () => _pickTime(draft.quietStart,
                        (v) => _draft = _draft!.withValue('quietStart', v))),
                ListTile(
                    title: const Text('安静时段结束'),
                    subtitle: Text(draft.quietEnd),
                    trailing: const Icon(Icons.schedule),
                    onTap: () => _pickTime(draft.quietEnd,
                        (v) => _draft = _draft!.withValue('quietEnd', v))),
              ])),
              if (_saving) const LinearProgressIndicator(),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                    child: FilledButton(
                        onPressed: _saving ? null : _save,
                        child: Text(_group.isEmpty ? '保存全局设置' : '保存该群设置'))),
                const SizedBox(width: 8),
                OutlinedButton(
                    onPressed: _saving || !_dirty
                        ? null
                        : () => setState(_resetDraft),
                    child: const Text('撤销')),
              ]),
              if (_group.isNotEmpty && config.groups.containsKey(_group))
                TextButton(
                    onPressed: _saving ? null : _clearGroupOverride,
                    child: const Text('清除该群单独设置，全部跟随全局')),
            ]));
  }

  Widget _statusCard(
      ProactiveReplyGroupStatus? s, Set<String> overridden) {
    return Card(
        margin: const EdgeInsets.only(top: 12),
        child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SelectableText('群 OpenID：$_group',
                  style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 4),
              if (s == null)
                const Text('还没有收到这个群的消息记录')
              else ...[
                Text('今日已插话 ${s.today} 次 · 上次插话 ${_ago(s.lastReply)}'),
                Text('最近消息：${_ago(s.lastSeen)} ${s.lastSender}：${s.lastText}',
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                Text('上次插话后又收到 ${s.sinceReply} 条消息'),
                if (s.lastResult.isNotEmpty)
                  Text('最近一次尝试：${_ago(s.lastAttempt)} ${s.lastResult}'),
                if (s.lastTestResult.isNotEmpty)
                  Text('最近一次测试：${_ago(s.lastTest)} ${s.lastTestResult}'),
              ],
              const SizedBox(height: 8),
              Row(children: [
                OutlinedButton.icon(
                    onPressed: _testing ? null : _test,
                    icon: _testing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.send, size: 18),
                    label: Text(_testing ? '生成中…' : '立即测试一次')),
                const SizedBox(width: 8),
                const Expanded(
                    child: Text('跳过概率、冷却和次数限制，回复群里最近一条消息（需 4.5 分钟内有人发言）',
                        style: TextStyle(fontSize: 12, color: Colors.grey))),
              ]),
            ])));
  }

  Widget _numberField((String, String, String) f, Set<String> overridden) {
    final range = proactiveReplyRanges[f.$1]!;
    final mark = _group.isNotEmpty && overridden.contains(f.$1) ? ' *' : '';
    return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: TextField(
            controller: _controllers[f.$1],
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
                labelText: '${f.$2}$mark',
                suffixText: f.$3,
                helperText: '${range.min}–${range.max}',
                isDense: true),
            onChanged: (v) {
              final parsed = int.tryParse(v);
              if (parsed != null) {
                setState(() => _draft = _draft!.withValue(f.$1, parsed));
              }
            }));
  }

  Future<void> _pickTime(String current, void Function(String) apply) async {
    final parts = current.split(':');
    final picked = await showTimePicker(
        context: context,
        initialTime: TimeOfDay(
            hour: int.tryParse(parts.first) ?? 0,
            minute: int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0));
    if (picked != null && mounted) {
      setState(() => apply(
          '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}'));
    }
  }
}
