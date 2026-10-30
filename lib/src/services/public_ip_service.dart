import 'dart:convert';
import 'dart:io';
import '../models/public_ip.dart';

typedef PublicIpFetcher = Future<String?> Function(String endpoint);

class PublicIpService {
  const PublicIpService(
      {this.ipv4Endpoint = 'https://api.ipify.org?format=json',
      this.ipv6Endpoint = 'https://api6.ipify.org?format=json',
      this.fetcher});
  final String ipv4Endpoint;
  final String ipv6Endpoint;
  final PublicIpFetcher? fetcher;

  Future<PublicIpResult> lookup() async {
    final now = DateTime.now();
    final lookup = fetcher ?? _fetch;
    final values =
        await Future.wait([lookup(ipv4Endpoint), lookup(ipv6Endpoint)]);
    final ipv4 = values[0];
    final ipv6 = values[1];
    return PublicIpResult(
      ipv4: ipv4,
      ipv6: ipv6,
      checkedAt: now,
      error: ipv4 == null && ipv6 == null ? '无法连接公网 IP 查询服务' : null,
    );
  }

  Future<String?> _fetch(String endpoint) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client
          .getUrl(Uri.parse(endpoint))
          .timeout(const Duration(seconds: 6));
      request.headers.set(HttpHeaders.acceptHeader, ContentType.json.mimeType);
      final response =
          await request.close().timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) return null;
      final body = await response.transform(utf8.decoder).join();
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['ip'] is String)
        return decoded['ip'] as String;
      return null;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }
}
