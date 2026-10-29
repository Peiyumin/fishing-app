import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../utils/text_safe.dart';
import 'api_config.dart';
import '../utils/json_num.dart';

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

/// 传输层失败：**请求根本没到服务器，或者回包半路断了**。
///
/// 为什么必须跟 [ApiException] 分开（v2.1.52）：
///   · [ApiException] 是「服务器说话了，但说的是错误」（手机号格式不对、
///     验证码错了、接口不存在……）—— 这类错误重试一百次也是同样的结果，
///     文案必须原样告诉用户；
///   · [ApiNetException] 是「压根没连上 / 连接被掐断」—— 这类错误重试常常
///     就好了，文案要说「网络」而不是把服务器原话抛给用户。
///
/// 以前登录页拿 `e.toString().contains('Connection')` 判断网络 —— 结果
/// `HttpException: Connection closed before full header was received`
/// （切后台后复用了被系统回收的空闲连接，iOS 上很常见）被说成「连不上
/// 服务器」，而它其实是**请求已经发出去、回包被掐断**，重试一次就好。
class ApiNetException implements Exception {
  const ApiNetException(this.kind, this.detail);

  /// connect（连不上） / timeout（等太久） / broken（连接被中断）
  final String kind;

  /// 底层真实原因，排查用（界面上只在「详情」里露出来）
  final String detail;

  /// 会不会是「重试一下就好」的类型。三种都算。
  bool get retryable => true;

  @override
  String toString() => detail;
}

/// 轻量 HTTP 客户端：JSON 请求 + 手写 multipart 图片上传（零第三方依赖）
class ApiClient {
  static String? _token;
  static void setToken(String? t) => _token = t;
  static String? get token => _token;

  /// 最近一次失败的传输层原因（null = 最近一次请求成功）
  ///
  /// 只给排查用：登录页失败时把它带进 toast 的 detail，用户报「连不上」时
  /// 一句就能定位是超时、没网还是被拒绝，不用再猜。
  static ApiNetException? lastNetError;

  static final HttpClient _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 6)
    // ★ 空闲连接 3 秒就丢。
    //   iOS 把 App 切到后台后，系统会悄悄回收 socket，dart:io 并不知道，
    //   下次复用这条「看起来还在」的连接必然失败 —— 用户切回 App 点
    //   「获取验证码」，看到的就是「连不上服务器」。设短之后宁可重连，
    //   也不要去复用一条可能已经死掉的连接。
    ..idleTimeout = const Duration(seconds: 3);

  /// 一次请求最多试几次。
  ///
  /// · GET / DELETE 幂等：连接类失败一律再来一次（掉一次包就失败太脆）。
  /// · POST 只有「连接根本没建立」（connect）才敢重发 —— 这种失败请求
  ///   一定没到服务器，重发不会撞上「发送太频繁」的 60 秒冷却；
  ///   `broken`（回包半路断了）**绝不能重发**：服务端可能已经收下并写库了，
  ///   重发等于连发两条。
  static int attemptsFor(String method, String? kind) {
    if (kind == null) return 1; // 业务错误，重试一百次也是同一个结果
    if (method == 'GET' || method == 'DELETE') return 2;
    return kind == 'connect' ? 2 : 1;
  }

  /// 统一出口：把传输层异常归一成 [ApiNetException]，并按需重试一次。
  static Future<T> _run<T>(
    String method,
    String path,
    Future<T> Function() body,
  ) async {
    for (var attempt = 1;; attempt++) {
      try {
        final v = await body();
        lastNetError = null;
        return v;
      } catch (e) {
        final net = asNetError(e);
        if (net == null) rethrow; // 业务错误，原样抛给调用方
        lastNetError = net;
        if (attempt < attemptsFor(method, net.kind)) {
          // 200ms 后再试一次：网络切换（WiFi↔4G）的瞬间、路由器 ARP 抖动
          // 都在这段时间里恢复，用户根本没机会看到报错。
          await Future<void>.delayed(Duration(milliseconds: 200 * attempt));
          continue;
        }
        throw net;
      }
    }
  }

  /// 测试入口：直接驱动 [_run] 的重试策略（不发真实请求）。
  ///
  /// 为什么值得单独开一个口：重试规则是「POST 只在连接没建立时重发」，
  /// 这条规则写错了就是「用户点一次发码，服务端收到两条」或者
  /// 「掉一次包就失败」。用假的 body 把两个分支都跑一遍最省事。
  static Future<T> runWithRetry<T>(
    String method,
    Future<T> Function() body,
  ) =>
      _run(method, '', body);

  /// 把 dart:io 的各种底层异常翻译成三种人话类别
  static ApiNetException? asNetError(Object e) {
    if (e is ApiNetException) return e;
    if (e is SocketException) {
      final m = e.message.trim().isNotEmpty
          ? e.message.trim()
          : (e.osError?.message ?? '');
      return ApiNetException('connect', m.isEmpty ? 'SocketException' : m);
    }
    if (e is HandshakeException) {
      return ApiNetException('connect', 'TLS 握手失败：${e.message}');
    }
    if (e is TimeoutException) {
      return const ApiNetException('timeout', '等待服务器响应超时');
    }
    if (e is HttpException) {
      final m = e.message;
      // 「连接已建立但回包断了」跟「连不上」是两回事：
      // 前者重试必好，后者要看网络/端口。
      final broken = RegExp(
        r'connection (closed|reset|terminated)|broken pipe|premature',
        caseSensitive: false,
      ).hasMatch(m);
      return ApiNetException(broken ? 'broken' : 'connect', m);
    }
    return null;
  }

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

  static Future<dynamic> get(String path, [Map<String, String>? query]) =>
      _run('GET', path, () async {
        final req = await _http.getUrl(Uri.parse(_buildUrl(path, query)));
        // 不复用空闲连接：宁可多握一次手，也不要撞上被系统回收的死 socket
        req.persistentConnection = false;
        _setHeaders(req);
        final res = await req.close();
        return _decode(await res.transform(_utf8).join());
      });

  static Future<dynamic> post(String path, [Map<String, dynamic>? data]) =>
      _run('POST', path, () async {
        final req = await _http.postUrl(Uri.parse(_buildUrl(path)));
        req.persistentConnection = false;
        _setHeaders(req);
        // 必须用 utf8 编码成字节再写入：dart:io 的 write(String) 默认按 latin1
        // 编码，含中文的昵称/内容会抛 ArgumentError（请求根本发不出去）
        req.add(utf8.encode(jsonEncode(data ?? {})));
        final res = await req.close();
        return _decode(await res.transform(_utf8).join());
      });

  /// 解码响应正文用的解码器。
  ///
  /// ★ 必须 `allowMalformed: true`：默认的 [utf8.decoder] 遇到非法字节会
  ///   直接抛 `FormatException`，一个坏字节就让整页报「服务器无响应」。
  ///   放开之后坏字节变成 U+FFFD，再由 [sanitizeDeep] 清掉 —— 只丢一个
  ///   字符，其余内容照常显示。
  static const Utf8Decoder _utf8 = Utf8Decoder(allowMalformed: true);

  static Future<dynamic> delete(String path) => _run('DELETE', path, () async {
        final req = await _http.deleteUrl(Uri.parse(_buildUrl(path)));
        req.persistentConnection = false;
        _setHeaders(req);
        final res = await req.close();
        return _decode(await res.transform(_utf8).join());
      });

  /// POST 但返回完整 JSON（不丢弃 ok/code/error），用于需要读取业务 code 的接口
  /// （如私信发送失败要区分 need_follow / need_member）。
  static Future<Map<String, dynamic>> postRaw(
          String path, Map<String, dynamic> data) =>
      _run('POST', path, () async {
        final req = await _http.postUrl(Uri.parse(_buildUrl(path)));
        req.persistentConnection = false;
        _setHeaders(req);
        req.add(utf8.encode(jsonEncode(data)));
        final res = await req.close();
        final body = await res.transform(_utf8).join();
        if (body.isEmpty) throw const ApiException('服务器无响应');
        final json = jsonDecode(body);
        if (json is Map) return sanitizeDeep(json.cast<String, dynamic>());
        throw const ApiException('响应格式错误');
      });

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
    req.persistentConnection = false;
    req.headers.set('Content-Type', 'multipart/form-data; boundary=$boundary');
    if (_token != null) req.headers.set('Authorization', 'Bearer $_token');
    req.add(bb.takeBytes());
    final res = await req.close();
    final data = _decode(await res.transform(_utf8).join());
    // 严格判 List：返回了非列表说明服务端出错，宁可报「上传失败」，
    // 也不要静默返回空列表 —— 否则界面会出现「发布成功但一张图都没有」。
    if (data is! List) throw const ApiException('上传失败：服务器返回格式不对');
    return List<String>.from(data.map((e) => e.toString()));
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
    req.persistentConnection = false;
    req.headers.set('Content-Type', 'multipart/form-data; boundary=$boundary');
    if (_token != null) req.headers.set('Authorization', 'Bearer $_token');
    req.add(bb.takeBytes());
    final res = await req.close();
    final data = _decode(await res.transform(_utf8).join());
    if (data is! List) throw const ApiException('上传失败：服务器返回格式不对');
    final list = List<String>.from(data.map((e) => e.toString()));
    if (list.isEmpty) throw const ApiException('上传失败：服务器未返回文件地址');
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
        status: json is Map ? (jsonInt(json['status']) ?? 0) : 0,
      );
    }
    return sanitizeDeep(json['data']);
  }
}
