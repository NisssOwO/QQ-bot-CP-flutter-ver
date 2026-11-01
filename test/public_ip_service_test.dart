import 'package:flutter_test/flutter_test.dart';
import 'package:qq_bot_cp/src/services/public_ip_service.dart';

void main() {
  test('keeps IPv4 and IPv6 results separate', () async {
    final result = await const PublicIpService(
      ipv4Endpoint: 'v4',
      ipv6Endpoint: 'v6',
      ipv4Fallbacks: [],
      ipv6Fallbacks: [],
      fetcher: _fakeFetcher,
    ).lookup();
    expect(result.ipv4, '203.0.113.10');
    expect(result.ipv6, '2001:db8::10');
    expect(result.error, isNull);
  });

  test('falls back to the next endpoint when the primary one times out', () async {
    final result = await const PublicIpService(
      ipv4Endpoint: 'dead',
      ipv6Endpoint: 'dead6',
      ipv4Fallbacks: ['backup'],
      ipv6Fallbacks: [],
      fetcher: _flakyFetcher,
    ).lookup();

    expect(result.ipv4, '198.51.100.7');
    expect(result.ipv6, isNull);
    expect(result.error, isNull);
  });

  test('reports a useful error when both endpoints fail', () async {
    final result =
        await const PublicIpService(fetcher: _failedFetcher).lookup();
    expect(result.ipv4, isNull);
    expect(result.ipv6, isNull);
    expect(result.error, contains('无法连接'));
  });
}

Future<String?> _fakeFetcher(String endpoint) async => switch (endpoint) {
      'v4' => '203.0.113.10',
      'v6' => '2001:db8::10',
      _ => null,
    };

Future<String?> _flakyFetcher(String endpoint) async =>
    endpoint == 'backup' ? '198.51.100.7' : null;

Future<String?> _failedFetcher(String endpoint) async => null;