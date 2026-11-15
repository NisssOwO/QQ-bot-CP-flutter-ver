import 'package:flutter_test/flutter_test.dart';
import 'package:qq_bot_cp/src/ai/ai_protocol.dart';
import 'package:qq_bot_cp/src/ai/protocol_registry.dart';

void main() {
  group('ProtocolRegistry.effectiveId', () {
    test('DeepSeek 地址会锁定为 OpenAI 兼容', () {
      expect(
        ProtocolRegistry.effectiveId(baseUrl: 'https://api.deepseek.com', selected: 'openai-responses'),
        AiProtocolKind.openaiCompatible.id,
      );
    });

    test('DeepSeek 地址大小写与子域都能识别', () {
      expect(ProtocolRegistry.isLocked(baseUrl: 'https://API.DeepSeek.com/v1'), isTrue);
      expect(ProtocolRegistry.effectiveId(baseUrl: 'https://API.DeepSeek.com/v1', selected: 'anthropic-messages'), 'openai-compatible');
    });

    test('非 DeepSeek 地址保留用户选择', () {
      expect(ProtocolRegistry.effectiveId(baseUrl: 'https://api.openai.com/v1', selected: 'openai-responses'), 'openai-responses');
      expect(ProtocolRegistry.effectiveId(baseUrl: 'https://api.anthropic.com', selected: 'anthropic-messages'), 'anthropic-messages');
    });

    test('未选择协议时回落到 OpenAI 兼容', () {
      expect(ProtocolRegistry.effectiveId(baseUrl: 'https://relay.example.com/v1', selected: ''), 'openai-compatible');
      expect(ProtocolRegistry.effectiveId(baseUrl: 'https://relay.example.com/v1', selected: '   '), 'openai-compatible');
    });

    test('未知协议名回落到 OpenAI 兼容', () {
      expect(ProtocolRegistry.effectiveId(baseUrl: 'https://relay.example.com/v1', selected: 'openai-completions'), 'openai-compatible');
    });

    test('非 DeepSeek 地址不锁定', () {
      expect(ProtocolRegistry.isLocked(baseUrl: 'https://api.openai.com/v1'), isFalse);
      expect(ProtocolRegistry.isLocked(baseUrl: ''), isFalse);
    });
  });

  group('ProtocolRegistry.effectiveThinkingLevel', () {
    test('DeepSeek 地址固定关闭思考', () {
      expect(ProtocolRegistry.effectiveThinkingLevel(baseUrl: 'https://api.deepseek.com', selected: 'high'), 'off');
      expect(ProtocolRegistry.isThinkingLocked(baseUrl: 'https://api.deepseek.com'), isTrue);
    });

    test('DeepSeek 地址大小写与子域同样锁定', () {
      expect(ProtocolRegistry.effectiveThinkingLevel(baseUrl: 'https://API.DeepSeek.com/v1', selected: 'medium'), 'off');
      expect(ProtocolRegistry.isThinkingLocked(baseUrl: 'https://API.DeepSeek.com/v1'), isTrue);
    });

    test('非 DeepSeek 地址保留合法选择', () {
      expect(ProtocolRegistry.effectiveThinkingLevel(baseUrl: 'https://api.openai.com/v1', selected: 'high'), 'high');
      expect(ProtocolRegistry.effectiveThinkingLevel(baseUrl: 'https://api.openai.com/v1', selected: 'low'), 'low');
      expect(ProtocolRegistry.isThinkingLocked(baseUrl: 'https://api.openai.com/v1'), isFalse);
    });

    test('非法或空值回落到默认档', () {
      expect(ProtocolRegistry.effectiveThinkingLevel(baseUrl: 'https://relay.example.com/v1', selected: ''), ProtocolRegistry.thinkingLevelDefault);
      expect(ProtocolRegistry.effectiveThinkingLevel(baseUrl: 'https://relay.example.com/v1', selected: 'ultra'), ProtocolRegistry.thinkingLevelDefault);
    });
  });
}
