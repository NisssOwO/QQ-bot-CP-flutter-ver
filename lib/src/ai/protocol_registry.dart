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
}
