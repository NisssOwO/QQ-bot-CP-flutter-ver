import 'package:flutter_test/flutter_test.dart';
import 'package:qq_bot_cp/src/services/public_ip_service.dart';

void main() {
  test('keeps IPv4 and IPv6 results separate', () async {
    final result = await const PublicIpService(
      ipv4Endpoint: 'v4',
      ipv6Endpoint: 'v6',
      fetcher: _fakeFetcher,
    ).lookup();
    expect(result.ipv4, '203.0.113.10');
    expect(result.ipv6, '2001:db8::10');
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

Future<String?> _fakeFetcher(String endpoint) async =>
    endpoint == 'v4' ? '203.0.113.10' : '2001:db8::10';
Future<String?> _failedFetcher(String endpoint) async => null;
