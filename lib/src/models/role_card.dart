import 'package:flutter/foundation.dart';

@immutable
class RoleCard {
  const RoleCard({required this.id, required this.displayName, required this.prompt, this.builtin = false});
  final String id;
  final String displayName;
  final String prompt;
  final bool builtin;

  factory RoleCard.fromMap(Map<dynamic, dynamic> raw) => RoleCard(id: '${raw['id'] ?? ''}', displayName: '${raw['displayName'] ?? raw['name'] ?? ''}', prompt: '${raw['prompt'] ?? ''}', builtin: raw['builtin'] == true);
  Map<String, Object?> toMap() => {'id': id, 'displayName': displayName, 'prompt': prompt, 'builtin': builtin};
}
