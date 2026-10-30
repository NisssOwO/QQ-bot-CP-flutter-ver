import 'dart:convert';
import 'dart:io';
import '../models/update_manifest.dart';

class UpdateService {
  const UpdateService();

  Future<UpdateManifest> check(String endpoint) async {
    final uri = Uri.tryParse(endpoint.trim());
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https') || uri.host.isEmpty) throw const FormatException('更新清单 URL 无效');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client.getUrl(uri).timeout(const Duration(seconds: 6));
      final response = await request.close().timeout(const Duration(seconds: 8));
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode != 200) throw HttpException('更新清单返回 HTTP ${response.statusCode}');
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) throw const FormatException('更新清单格式错误');
      return UpdateManifest.fromJson(decoded);
    } finally {
      client.close(force: true);
    }
  }

  Future<void> download(UpdateManifest manifest, String path, {required void Function(int received, int total) onProgress}) async {
    final uri = Uri.tryParse(manifest.apkUrl);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https') || uri.host.isEmpty) throw const FormatException('APK 下载地址无效');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.getUrl(uri).timeout(const Duration(seconds: 10));
      final response = await request.close().timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) throw HttpException('APK 下载返回 HTTP ${response.statusCode}');
      final total = response.contentLength > 0 ? response.contentLength : manifest.sizeBytes;
      var received = 0;
      final file = File(path);
      await file.parent.create(recursive: true);
      final sink = file.openWrite();
      try {
        await for (final chunk in response) { sink.add(chunk); received += chunk.length; onProgress(received, total); }
      } finally { await sink.close(); }
    } finally { client.close(force: true); }
  }
}
