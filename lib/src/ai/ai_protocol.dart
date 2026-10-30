import 'dart:async';

enum AiProtocolKind { openaiCompatible, openaiResponses, anthropicMessages }

extension AiProtocolKindLabel on AiProtocolKind {
  String get id => switch (this) {
    AiProtocolKind.openaiCompatible => 'openai-compatible',
    AiProtocolKind.openaiResponses => 'openai-responses',
    AiProtocolKind.anthropicMessages => 'anthropic-messages',
  };

  String get label => switch (this) {
    AiProtocolKind.openaiCompatible => 'OpenAI Compatible',
    AiProtocolKind.openaiResponses => 'OpenAI Responses',
    AiProtocolKind.anthropicMessages => 'Anthropic Messages',
  };
}

class AiProtocolCapabilities {
  const AiProtocolCapabilities({required this.streaming, required this.vision, required this.toolCalls, required this.reasoning});
  final bool streaming;
  final bool vision;
  final bool toolCalls;
  final bool reasoning;
}

class AiMessage {
  const AiMessage({required this.role, required this.content});
  final String role;
  final String content;
}

class AiRequest {
  const AiRequest({required this.model, required this.messages, this.temperature});
  final String model;
  final List<AiMessage> messages;
  final double? temperature;
}

class AiResponse {
  const AiResponse({required this.text, this.finishReason});
  final String text;
  final String? finishReason;
}

class AiProtocolError implements Exception {
  const AiProtocolError({required this.code, required this.message, this.statusCode, this.retryable = false});
  final String code;
  final String message;
  final int? statusCode;
  final bool retryable;
  @override String toString() => '$code: $message';
}

abstract interface class AiProtocolAdapter {
  AiProtocolKind get kind;
  AiProtocolCapabilities get capabilities;
  Future<List<String>> listModels();
  Future<AiResponse> complete(AiRequest request);
  Stream<String> stream(AiRequest request);
  Future<void> cancel();
}

AiProtocolError normalizeAiError(Object error, {int? statusCode}) {
  if (error is AiProtocolError) return error;
  if (error is TimeoutException) return AiProtocolError(code: 'timeout', message: 'AI 请求超时', statusCode: statusCode, retryable: true);
  if (error is FormatException) return AiProtocolError(code: 'invalid_response', message: 'AI 返回格式无法解析', statusCode: statusCode);
  return AiProtocolError(code: 'transport_error', message: '$error', statusCode: statusCode, retryable: true);
}
