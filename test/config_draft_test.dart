import 'package:flutter_test/flutter_test.dart';
import 'package:qq_bot_cp/src/services/config_draft.dart';

void main() {
  const saved = LlmConfigDraft(
    protocol: 'openai-responses',
    model: 'deepseek-flash',
    baseUrl: 'https://api.deepseek.com',
    thinkingLevel: '低',
    appId: '100000000',
    apiKey: 'sk-saved-key',
    secret: 'saved-secret',
  );

  test('identical drafts are not dirty', () {
    expect(hasUnsavedConfigChanges(current: saved, saved: saved), isFalse);
  });

  test('masked credentials count as saved content', () {
    const current = LlmConfigDraft(
      protocol: 'openai-responses',
      model: 'deepseek-flash',
      baseUrl: 'https://api.deepseek.com',
      thinkingLevel: '低',
      appId: '100000000',
      apiKey: maskedCredential,
      secret: maskedCredential,
    );
    expect(hasUnsavedConfigChanges(current: current, saved: saved), isFalse);
  });

  test('a wrong key typed into the form only marks the draft dirty', () {
    final typed = saved.copyWith(apiKey: 'wrongkey000');
    expect(hasUnsavedConfigChanges(current: typed, saved: saved), isTrue);
    // 失败测试不会回写已保存的配置：快照本身没有被修改
    expect(saved.apiKey, 'sk-saved-key');
    expect(saved.secret, 'saved-secret');
    expect(typed == saved, isFalse);
  });

  test('copyWith keeps the saved snapshot untouched', () {
    final draft = saved.copyWith(baseUrl: 'https://relay.example.com', model: 'other-model');
    expect(saved.baseUrl, 'https://api.deepseek.com');
    expect(saved.model, 'deepseek-flash');
    expect(draft.baseUrl, 'https://relay.example.com');
  });

  test('whitespace around text fields is ignored', () {
    final padded = saved.copyWith(baseUrl: ' https://api.deepseek.com ', appId: ' 100000000 ');
    expect(hasUnsavedConfigChanges(current: padded, saved: saved), isFalse);
  });

  test('changing protocol or thinking level is a real change', () {
    expect(hasUnsavedConfigChanges(current: saved.copyWith(protocol: 'anthropic-messages'), saved: saved), isTrue);
    expect(hasUnsavedConfigChanges(current: saved.copyWith(thinkingLevel: '高'), saved: saved), isTrue);
  });
}