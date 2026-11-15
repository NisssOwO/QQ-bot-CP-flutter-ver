import 'ai_protocol.dart';

class ProtocolDescriptor {
  const ProtocolDescriptor({required this.kind, required this.capabilities});
  final AiProtocolKind kind;
  final AiProtocolCapabilities capabilities;
}

class ProtocolRegistry {
  static const descriptors = <ProtocolDescriptor>[
    ProtocolDescriptor(kind: AiProtocolKind.openaiCompatible, capabilities: AiProtocolCapabilities(streaming: true, vision: true, toolCalls: true, reasoning: false)),
    ProtocolDescriptor(kind: AiProtocolKind.openaiResponses, capabilities: AiProtocolCapabilities(streaming: true, vision: true, toolCalls: true, reasoning: true)),
    ProtocolDescriptor(kind: AiProtocolKind.anthropicMessages, capabilities: AiProtocolCapabilities(streaming: true, vision: true, toolCalls: true, reasoning: true)),
  ];

  static ProtocolDescriptor? find(String id) => descriptors.where((item) => item.kind.id == id).firstOrNull;

  /// 界面显示的"实际生效"协议——必须和 Android 侧 `RuntimeService.kt` 的 LLM_API
  /// 推导保持同一套规则，否则设置页会显示一个运行时并不使用的值。
  ///
  /// Base URL 指向 DeepSeek 时固定走 OpenAI 兼容（pi-ai 的 completions 路径），
  /// 因为服务端联网搜索只在这条路径上验证可用；其余情况沿用已保存的选择，
  /// 缺省回落到 OpenAI 兼容。
  static String effectiveId({required String baseUrl, required String selected}) {
    if (_isDeepSeek(baseUrl)) return AiProtocolKind.openaiCompatible.id;
    final value = selected.trim();
    if (value == AiProtocolKind.openaiResponses.id || value == AiProtocolKind.anthropicMessages.id) return value;
    return AiProtocolKind.openaiCompatible.id;
  }

  /// 协议被 Base URL 锁定（用户不能再手选）时为 true。
  static bool isLocked({required String baseUrl}) => _isDeepSeek(baseUrl);

  /// "思考程度"的实际生效值，同样由接口决定。
  ///
  /// DeepSeek：服务端联网搜索固定走普通模式（深度思考搜索会把整页正文塞进上下文，
  /// 一轮能烧到两万多 prompt tokens），所以这里恒为关闭，用户改不了。
  /// 其他接口：运行时本来就不向上游传思考等级，保留用户的历史选择没有意义，
  /// 但也没有可靠的推导依据，于是维持原值，避免界面凭空改掉别人的配置。
  static String effectiveThinkingLevel({required String baseUrl, required String selected}) {
    if (_isDeepSeek(baseUrl)) return thinkingLevelOff;
    final value = selected.trim();
    if (thinkingLevels.contains(value)) return value;
    return thinkingLevelDefault;
  }

  /// 思考程度被接口锁定（用户不能再手选）时为 true。
  static bool isThinkingLocked({required String baseUrl}) => _isDeepSeek(baseUrl);

  static const String thinkingLevelOff = 'off';
  static const String thinkingLevelDefault = 'medium';
  static const List<String> thinkingLevels = ['off', 'low', 'medium', 'high'];

  static bool _isDeepSeek(String baseUrl) => baseUrl.trim().toLowerCase().contains('deepseek.com');
}
