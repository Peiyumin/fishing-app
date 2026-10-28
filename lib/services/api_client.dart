import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../utils/text_safe.dart';
import 'api_config.dart';

/// 接口错误。
///
/// v2.1.49 新增。以前所有失败都抛裸 `Exception(文案)`，调用方只能靠
/// `e.toString().contains('404')` 这种字符串匹配去猜是哪种失败 —— 结果就是
/// 「用户不存在」被当成「后端没升级」，给用户弹了一句莫名其妙的话。
///
/// 现在把三件事分开带出来：
///   · [message] 服务器给的**人话**（`{"ok":false,"error":"用户不存在"}`）
///   · [status]  业务状态码（后端 v38 起放在 `status` 字段，缺省 0）
///   · [html]    响应是不是 HTML 错误页（nginx 404 页 / PHP 致命错误页）
class ApiException implements Exception {
  const ApiException(this.message, {this.status = 0, this.html = false});

  final String message;
  final int status;
  final bool html;

  @override
  String toString() => message;
}

/// 轻量 HTTP 客户端：JSON 请求 + 手写 multipart 图片上传（零第三方依赖）
class ApiClient {
  static String? _token;
  static void setToken(String? t) => _token = t;
  static String? get token => _token;

  static final HttpClient _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 8);

  /// 统一构造请求地址。
  /// PHP 后端通过前端控制器 api/index.php 的 ?r= 路由分发，
  /// 无需服务器 rewrite 配置，Apache/Nginx/内置服务器全兼容。
  /// token 拼在 URL 参数里（部分网关会改写请求头，但保留 query 参数）。
  static String _buildUrl(String path, [Map<String, String>? query]) {
    final params = <String>[];
    if (query != null) {
      for (final e in query.entries) {
        params.add(
            '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}');
      }
    }
    if (_token != null) {
      params.add('access_token=${Uri.encodeComponent(_token!)}');
    }
    final q = params.isEmpty ? '' : '&${params.join('&')}';
    return '${ApiConfig.baseUrl}/index.php?r=$path$q';
  }

  static void _setHeaders(HttpClientRequest req) {
    req.headers.set('Content-Type', 'application/json');
    if (_token != null) req.headers.set('Authorization', 'Bearer $_token');
  }

  static Future<dynamic> get(String path, [Map<String, String>? query]) async {
    final req = await _http.getUrl(Uri.parse(_buildUrl(path, query)));
    _setHeaders(req);
    final res = await req.close();
    return _decode(await res.transform(_utf8).join());
  }

  static Future<dynamic> post(String path, [Map<String, dynamic>? data]) async {
    final req = await _http.postUrl(Uri.parse(_buildUrl(path)));
    _setHeaders(req);
    // 必须用 utf8 编码成字节再写入：dart:io 的 write(String) 默认按 latin1
    // 编码，含中文的昵称/内容会抛 ArgumentError（请求根本发不出去）
    req.add(utf8.encode(jsonEncode(data ?? {})));
    final res = await req.close();
    return _decode(await res.transform(_utf8).join());
  }

  /// 解码响应正文用的解码器。
  ///
  /// ★ 必须 `allowMalformed: true`：默认的 [utf8.decoder] 遇到非法字节会
  ///   直接抛 `FormatException`，一个坏字节就让整页报「服务器无响应」。
  ///   放开之后坏字节变成 U+FFFD，再由 [sanitizeDeep] 清掉 —— 只丢一个
  ///   字符，其余内容照常显示。
  static const Utf8Decoder _utf8 = Utf8Decoder(allowMalformed: true);

  static Future<dynamic> delete(String path) async {
    final req = await _http.deleteUrl(Uri.parse(_buildUrl(path)));
    _setHeaders(req);
    final res = await req.close();
    return _decode(await res.transform(_utf8).join());
  }

  /// POST 但返回完整 JSON（不丢弃 ok/code/error），用于需要读取业务 code 的接口
  /// （如私信发送失败要区分 need_follow / need_member）。
  static Future<Map<String, dynamic>> postRaw(
      String path, Map<String, dynamic> data) async {
    final req = await _http.postUrl(Uri.parse(_buildUrl(path)));
    _setHeaders(req);
    req.add(utf8.encode(jsonEncode(data)));
    final res = await req.close();
    final body = await res.transform(_utf8).join();
    if (body.isEmpty) throw Exception('服务器无响应');
    final json = jsonDecode(body);
    if (json is Map) return sanitizeDeep(json.cast<String, dynamic>());
    throw Exception('响应格式错误');
  }

  /// 上传图片（multipart/form-data），返回服务器图片路径列表（绝对 URL）。
  /// 字段名用 file[]：PHP 对同名普通字段只保留一个，带 [] 才会聚合成数组。
  /// [watermark] = true 时带 ?wm=1，后端按后台水印配置自动叠加水印（头像上传不走这里）。
  static Future<List<String>> uploadImages(
    List<String> filePaths, {
    bool watermark = false,
  }) async {
    final boundary = 'dart-fishing-${DateTime.now().millisecondsSinceEpoch}';
    final bb = BytesBuilder();
    for (final path in filePaths) {
      final bytes = await File(path).readAsBytes();
      final name = path.split('/').last.split('\\').last;
      bb.add(utf8.encode('--$boundary\r\n'));
      bb.add(utf8.encode(
          'Content-Disposition: form-data; name="file[]"; filename="$name"\r\n'));
      bb.add(utf8.encode('Content-Type: image/jpeg\r\n\r\n'));
      bb.add(bytes);
      bb.add(utf8.encode('\r\n'));
    }
    bb.add(utf8.encode('--$boundary--\r\n'));

    final req = await _http.postUrl(Uri.parse(_buildUrl(
      '/upload',
      watermark ? {'wm': '1'} : null,
    )));
    req.headers.set('Content-Type', 'multipart/form-data; boundary=$boundary');
    if (_token != null) req.headers.set('Authorization', 'Bearer $_token');
    req.add(bb.takeBytes());
    final res = await req.close();
    final data = _decode(await res.transform(_utf8).join());
    return List<String>.from(data as List);
  }

  /// 上传单个文件（头像图片 / 视频），返回服务器文件地址（绝对 URL）。
  /// 字段名用 file（不带 []）：PHP 对单个文件走非数组分支。
  /// contentType 仅作声明，PHP 按扩展名判定类型。
  static Future<String> uploadFile(
    String filePath, {
    String contentType = 'application/octet-stream',
  }) async {
    final boundary = 'dart-fishing-${DateTime.now().millisecondsSinceEpoch}';
    final bb = BytesBuilder();
    final bytes = await File(filePath).readAsBytes();
    final name = filePath.split('/').last.split('\\').last;
    bb.add(utf8.encode('--$boundary\r\n'));
    bb.add(utf8.encode(
        'Content-Disposition: form-data; name="file"; filename="$name"\r\n'));
    bb.add(utf8.encode('Content-Type: $contentType\r\n\r\n'));
    bb.add(bytes);
    bb.add(utf8.encode('\r\n'));
    bb.add(utf8.encode('--$boundary--\r\n'));

    final req = await _http.postUrl(Uri.parse(_buildUrl('/upload')));
    req.headers.set('Content-Type', 'multipart/form-data; boundary=$boundary');
    if (_token != null) req.headers.set('Authorization', 'Bearer $_token');
    req.add(bb.takeBytes());
    final res = await req.close();
    final data = _decode(await res.transform(_utf8).join());
    final list = List<String>.from(data as List);
    if (list.isEmpty) throw Exception('上传失败：服务器未返回文件地址');
    return list.first;
  }

  /// 统一解析后端 {ok, data, error} 响应
  ///
  /// ★ 返回值里的**所有字符串都过了 [sanitizeDeep]**。
  ///   为什么放在这一层：昵称、钓点名、地址、评论来自用户输入 / 服务端 /
  ///   第三方地名接口，只要有一次 UTF-8 被从中间截断，客户端就会拿到
  ///   U+FFFD 或半个代理项 —— 在 Text 里就是一个小方块。挂在这里能一次
  ///   覆盖全站，比在每个 model 的 fromJson 里各写一遍可靠得多。
  static dynamic _decode(String body) {
    if (body.isEmpty) throw const ApiException('服务器无响应');
    // ★ 服务端返回了 HTML（nginx 的 404/502 错误页、PHP 致命错误页）。
    //   直接把 "<html>" 丢给 jsonDecode 会抛 `FormatException: Unexpected
    //   character (at character 1) <html>`，用户完全看不懂这是什么意思。
    //   宁可给一句人话，也不要暴露内部细节。
    final head = body.trimLeft();
    if (head.startsWith('<')) {
      throw const ApiException('服务器开小差了，请稍后再试', html: true);
    }
    final json = jsonDecode(body);
    if (json is! Map || json['ok'] != true) {
      throw ApiException(
        json is Map ? safeText(json['error'] ?? '请求失败') : '请求失败',
        status: json is Map ? ((json['status'] as num?)?.toInt() ?? 0) : 0,
      );
    }
    return sanitizeDeep(json['data']);
  }
}
