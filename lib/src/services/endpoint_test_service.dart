import 'dart:async';
import 'dart:io';
import '../models/endpoint_test_result.dart';

class EndpointTestService {
  const EndpointTestService();

  Future<EndpointTestResult> test(String value) async {
    final uri = Uri.tryParse(value.trim());
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https') || uri.host.isEmpty) {
      return const EndpointTestResult(ok: false, stage: '输入', message: 'Base URL 不是有效的 HTTP/HTTPS 地址');
    }
    final timer = Stopwatch()..start();
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client.getUrl(uri).timeout(const Duration(seconds: 6));
      final response = await request.close().timeout(const Duration(seconds: 8));
      await response.drain<void>();
      timer.stop();
      return EndpointTestResult(ok: response.statusCode < 500, stage: uri.scheme == 'https' ? 'TLS/HTTP' : 'HTTP', message: response.statusCode < 500 ? '接口地址可连接' : '服务器返回错误', statusCode: response.statusCode, elapsedMs: timer.elapsedMilliseconds);
    } on SocketException catch (error) {
      timer.stop();
      return EndpointTestResult(ok: false, stage: 'DNS/网络', message: error.message, elapsedMs: timer.elapsedMilliseconds);
    } on HandshakeException catch (error) {
      timer.stop();
      return EndpointTestResult(ok: false, stage: 'TLS', message: error.message, elapsedMs: timer.elapsedMilliseconds);
    } on TimeoutException {
      timer.stop();
      return EndpointTestResult(ok: false, stage: '超时', message: '连接超过 8 秒未完成', elapsedMs: timer.elapsedMilliseconds);
    } catch (error) {
      timer.stop();
      return EndpointTestResult(ok: false, stage: 'HTTP', message: '$error', elapsedMs: timer.elapsedMilliseconds);
    } finally {
      client.close(force: true);
    }
  }
}
