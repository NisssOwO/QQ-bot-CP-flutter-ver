/// 配置页里"已保存"与"正在编辑"两份内容的比较规则。
///
/// 保存只发生在用户点保存时；测试接口、拉取模型、测试请求失败都只影响
/// 当前草稿，不会写回已保存的配置。这里把这些规则集中成纯函数，
/// 便于离线测试"失败不覆盖旧配置"的行为。
library;

/// 已保存凭据在输入框里的占位符。
const String maskedCredential = '••••••••';

/// LLM / QQ 配置的一份快照，可以表示草稿，也可以表示已保存内容。
class LlmConfigDraft {
  const LlmConfigDraft({
    this.protocol = '',
    this.model = '',
    this.baseUrl = '',
    this.thinkingLevel = '',
    this.appId = '',
    this.apiKey = '',
    this.secret = '',
  });

  final String protocol;
  final String model;
  final String baseUrl;
  final String thinkingLevel;
  final String appId;
  final String apiKey;
  final String secret;

  LlmConfigDraft copyWith({
    String? protocol,
    String? model,
    String? baseUrl,
    String? thinkingLevel,
    String? appId,
    String? apiKey,
    String? secret,
  }) => LlmConfigDraft(
        protocol: protocol ?? this.protocol,
        model: model ?? this.model,
        baseUrl: baseUrl ?? this.baseUrl,
        thinkingLevel: thinkingLevel ?? this.thinkingLevel,
        appId: appId ?? this.appId,
        apiKey: apiKey ?? this.apiKey,
        secret: secret ?? this.secret,
      );

  @override
  bool operator ==(Object other) =>
      other is LlmConfigDraft &&
      other.protocol == protocol &&
      other.model == model &&
      other.baseUrl == baseUrl &&
      other.thinkingLevel == thinkingLevel &&
      other.appId == appId &&
      other.apiKey == apiKey &&
      other.secret == secret;

  @override
  int get hashCode => Object.hash(protocol, model, baseUrl, thinkingLevel, appId, apiKey, secret);
}

/// 草稿是否和已保存内容不同。
///
/// 凭据框里显示的是占位符，因此只要用户没有改动（还是占位符）或清空，
/// 就视为没有修改；用户键入任何新值都算修改，但不会影响已保存的密钥。
bool hasUnsavedConfigChanges({
  required LlmConfigDraft current,
  required LlmConfigDraft saved,
  String mask = maskedCredential,
}) {
  bool credentialChanged(String value, String savedValue) =>
      value.isNotEmpty && value != mask && value != savedValue;
  return current.protocol.trim() != saved.protocol.trim() ||
      current.model.trim() != saved.model.trim() ||
      current.baseUrl.trim() != saved.baseUrl.trim() ||
      current.thinkingLevel != saved.thinkingLevel ||
      current.appId.trim() != saved.appId.trim() ||
      credentialChanged(current.apiKey, saved.apiKey) ||
      credentialChanged(current.secret, saved.secret);
}