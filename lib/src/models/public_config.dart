import 'package:flutter/foundation.dart';

@immutable
class PublicConfig {
  const PublicConfig({
    this.protocol = '',
    this.model = '',
    this.baseUrl = '',
    this.thinkingLevel = 'medium',
    this.appId = '',
    this.qqConfigured = false,
    this.llmConfigured = false,
  });

  final String protocol;
  final String model;
  final String baseUrl;
  final String thinkingLevel;
  final String appId;
  final bool qqConfigured;
  final bool llmConfigured;

  PublicConfig copyWith({
    String? protocol,
    String? model,
    String? baseUrl,
    String? thinkingLevel,
    String? appId,
    bool? qqConfigured,
    bool? llmConfigured,
  }) =>
      PublicConfig(
        protocol: protocol ?? this.protocol,
        model: model ?? this.model,
        baseUrl: baseUrl ?? this.baseUrl,
        thinkingLevel: thinkingLevel ?? this.thinkingLevel,
        appId: appId ?? this.appId,
        qqConfigured: qqConfigured ?? this.qqConfigured,
        llmConfigured: llmConfigured ?? this.llmConfigured,
      );
}

@immutable
class AiConfigHistory {
  const AiConfigHistory(
      {required this.protocol, required this.model, required this.baseUrl});
  final String protocol;
  final String model;
  final String baseUrl;

  String get label =>
      '${protocol.isEmpty ? '未指定接口' : protocol} · ${model.isEmpty ? '未指定模型' : model}';
}
