import 'dart:convert';
import 'dart:io';
import '../models/update_manifest.dart';
import 'background_tasks.dart';

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
      final decoded = await decodeJsonInBackground(body);
      if (decoded is! Map<String, dynamic>) throw const FormatException('更新清单格式错误');
      final manifest = UpdateManifest.fromJson(decoded);
      manifest.validate();
      return manifest;
    } finally {
      client.close(force: true);
    }
  }

  Future<UpdateDownloadController> createDownload(UpdateManifest manifest, String path, {required void Function(int received, int total) onProgress}) async {
    final controller = UpdateDownloadController(manifest, path, onProgress);
    await controller.start();
    return controller;
  }

  Future<void> download(UpdateManifest manifest, String path, {required void Function(int received, int total) onProgress}) async {
    final controller = UpdateDownloadController(manifest, path, onProgress);
    await controller.start();
  }
}

class UpdateDownloadController {
  UpdateDownloadController(this.manifest, this.path, this.onProgress);
  final UpdateManifest manifest;
  final String path;
  final void Function(int received, int total) onProgress;
  HttpClient? _client;
  bool paused = false;
  bool cancelled = false;
  bool get active => _client != null;

  Future<void> start() async {
    paused = false;
    cancelled = false;
    final uri = Uri.tryParse(manifest.apkUrl);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https') || uri.host.isEmpty) throw const FormatException('APK 下载地址无效');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    _client = client;
    try {
      final file = File(path);
      final existing = await file.exists() ? await file.length() : 0;
      final request = await client.getUrl(uri).timeout(const Duration(seconds: 10));
      if (existing > 0) request.headers.set(HttpHeaders.rangeHeader, 'bytes=$existing-');
      final response = await request.close().timeout(const Duration(seconds: 15));
      if (response.statusCode != 200 && response.statusCode != 206) throw HttpException('APK 下载返回 HTTP ${response.statusCode}');
      final total = response.contentLength > 0 ? response.contentLength + (existing > 0 ? existing : 0) : manifest.sizeBytes;
      var received = existing;
      await file.parent.create(recursive: true);
      final sink = file.openWrite(mode: existing > 0 && response.statusCode == 206 ? FileMode.append : FileMode.write);
      try {
        await for (final chunk in response) { if (paused || cancelled) break; sink.add(chunk); received += chunk.length; onProgress(received, total); }
      } finally { await sink.close(); }
    } catch (error) {
      if (!paused && !cancelled) rethrow;
    } finally { _client = null; client.close(force: true); }
  }

  void pause() { paused = true; _client?.close(force: true); }
  void cancel() { cancelled = true; _client?.close(force: true); }
}
