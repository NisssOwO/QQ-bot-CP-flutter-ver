import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:qq_bot_cp_flutter/src/ai/ai_protocol.dart';
import 'package:qq_bot_cp_flutter/src/ai/protocol_registry.dart';

void main() {
  test('protocol registry exposes supported capabilities', () {
    expect(ProtocolRegistry.find('openai-compatible')?.capabilities.streaming, isTrue);
    expect(ProtocolRegistry.find('openai-responses')?.capabilities.reasoning, isTrue);
    expect(ProtocolRegistry.find('unknown'), isNull);
  });

  test('normalizes timeout into retryable error', () {
    final error = normalizeAiError(TimeoutException('late'));
    expect(error.code, 'timeout');
    expect(error.retryable, isTrue);
  });
}
