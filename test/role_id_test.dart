import 'package:flutter_test/flutter_test.dart';
import 'package:qq_bot_cp/src/services/role_id.dart';

void main() {
  test('generates a readable custom id from an English name', () {
    expect(generateRoleId('Calm Assistant', const []), 'custom.calm-assistant');
  });

  test('uses a safe fallback when the name has no latin slug', () {
    expect(generateRoleId('七草日花', const []), 'custom.role');
  });

  test('adds a suffix instead of overwriting an existing role', () {
    expect(
        generateRoleId('Calm Assistant',
            const ['custom.calm-assistant', 'custom.calm-assistant-2']),
        'custom.calm-assistant-3');
  });
}
