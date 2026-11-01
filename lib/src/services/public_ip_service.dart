import 'dart:convert';
import 'dart:io';
import '../models/public_ip.dart';

typedef PublicIpFetcher = Future<String?> Function(String endpoint);

/// 查询本机的公网地址。单一接口在移动网络下经常超时，所以每个地址族都准备了备用接口，
/// 全部并发发起，取第一个有效结果。
class PublicIpService {
  const PublicIpService({
    this.ipv4Endpoint = 'https://api.ipify.org?format=json',
    this.ipv6Endpoint = 'https://api6.ipify.org?format=json',
    this.ipv4Fallbacks = const ['https://ifconfig.me/ip', 'https://ipv4.icanhazip.com'],
    this.ipv6Fallbacks = const ['https://ipv6.icanhazip.com'],
    this.fetcher,
  });
  final String ipv4Endpoint;
  final String ipv6Endpoint;
  final List<String> ipv4Fallbacks;
  final List<String> ipv6Fallbacks;
  final PublicIpFetcher? fetcher;

  Future<PublicIpResult> lookup() async {
    final now = DateTime.now();
    final lookup = fetcher ?? _fetch;
    final values = await Future.wait([
      _first([ipv4Endpoint, ...ipv4Fallbacks], lookup),
      _first([ipv6Endpoint, ...ipv6Fallbacks], lookup),
    ]);
    final ipv4 = values[0];
    final ipv6 = values[1];
    return PublicIpResult(
      ipv4: ipv4,
      ipv6: ipv6,
      checkedAt: now,
      error: ipv4 == null && ipv6 == null ? '无法连接公网 IP 查询服务' : null,
    );
  }

  /// 并发请求同一地址族的全部接口，先返回的那个有效结果胜出。
  Future<String?> _first(List<String> endpoints, PublicIpFetcher lookup) async {
    if (endpoints.isEmpty) return null;
    final results = await Future.wait(endpoints.map(lookup));
    for (final value in results) {
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  Future<String?> _fetch(String endpoint) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
    try {
      final request = await client
          .getUrl(Uri.parse(endpoint))
          .timeout(const Duration(seconds: 5));
      request.headers.set(HttpHeaders.acceptHeader, ContentType.json.mimeType);
      final response =
          await request.close().timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) return null;
      final body = await response.transform(utf8.decoder).join();
      return _parse(body);
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// ipify 返回 {"ip": "..."}，ifconfig.me 一类接口直接返回地址本身。
  static String? _parse(String body) {
    final text = body.trim();
    if (text.startsWith('{')) {
      try {
        final decoded = jsonDecode(text);
        if (decoded is Map && decoded['ip'] is String) {
          return decoded['ip'] as String;
        }
      } catch (_) {
        return null;
      }
      return null;
    }
    if (text.isEmpty || text.contains(' ') || text.contains('\n')) return null;
    return InternetAddress.tryParse(text) == null ? null : text;
  }
}