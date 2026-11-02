import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'api_config.dart';

/// 一次连通性自检的结果。
///
/// 为什么需要它：用户报「连不上服务器」时，界面上只能说一句人话
/// （超时 / 没网 / 被拒绝），但到底是**这个端口根本连不通**，还是
/// **连得通只是接口回包有问题**，隔着屏幕猜不出来。真机上又不能看日志，
/// 所以做成一键自检：长按登录页图标，把两段结果都摆出来。
class NetDiagResult {
  /// TCP 能不能连上服务器端口（这一步和 HTTP 无关，纯网络）
  final bool tcpOk;
  final int tcpMs;
  final String tcpError;

  /// 接口能不能正常回 JSON（0 = 没走到这一步）
  final int httpStatus;
  final int httpMs;
  final String httpError;

  const NetDiagResult({
    required this.tcpOk,
    required this.tcpMs,
    required this.tcpError,
    required this.httpStatus,
    required this.httpMs,
    required this.httpError,
  });

  /// 给用户/排查看的一段话
  String get summary {
    final b = StringBuffer();
    b.writeln('服务器：${ApiConfig.baseUrl}');
    b.write('① 端口连通：');
    if (tcpOk) {
      b.writeln('通（${tcpMs}ms）');
    } else {
      b.writeln('不通（${tcpMs}ms）');
      b.writeln('   $tcpError');
      // 端口都连不上，HTTP 那一步没必要看了
      b.writeln('② 接口请求：未执行（先解决①）');
      b.writeln();
      b.writeln(_advice());
      return b.toString();
    }
    b.write('② 接口请求：');
    if (httpStatus > 0) {
      b.writeln('HTTP $httpStatus（${httpMs}ms）');
    } else {
      b.writeln('失败（${httpMs}ms）');
      b.writeln('   $httpError');
    }
    b.writeln();
    b.writeln(_advice());
    return b.toString();
  }

  String _advice() {
    if (!tcpOk) {
      final e = tcpError.toLowerCase();
      if (e.contains('timed out')) {
        return '判断：端口连不上且是「超时」＝请求发出去没人应答，\n'
            '通常是当前网络限制了 8801 端口。请让手机换一个网络\n'
            '（WiFi 换移动数据，或反过来）再试。';
      }
      if (e.contains('unreachable') || e.contains('no route')) {
        // iOS 把 App 的「无线数据」关掉时，socket 直接 ENETUNREACH ——
        // 这不是「手机没网」，说成没网会让用户去重启路由器白折腾。
        return Platform.isIOS
            ? '判断：请求没能离开手机 —— iOS 关掉本 App 的「无线数据」时\n'
                '就是这个表现。打开 设置 → 渔报 → 无线数据，选「无线\n'
                '局域网与蜂窝网络」，回来重新检测。'
            : '判断：手机没有可用出口网络。请确认移动数据/WiFi 已开，\n'
                '并在「设置 → 应用 → 渔报 → 流量使用」里允许联网。';
      }
      if (e.contains('refused')) {
        return '判断：服务器端口拒绝连接（服务没起或被防火墙拦）。\n'
            '这不是手机网络问题，需要检查服务器 8801 端口状态。';
      }
      return '判断：连不上服务器端口。请先换网络再试；\n'
          '如果换网络也一样，多半是服务器侧防火墙/安全组拦了这台设备的 IP。';
    }
    if (httpStatus == 200) {
      return '判断：网络和接口都正常 —— 如果页面仍提示失败，\n'
          '那是 App 侧的问题，把这张截图发我即可。';
    }
    return '判断：端口通但接口没回正常数据，多半是后端\n'
        '（PHP）出错或站点配置被改过，看②里的状态码。';
  }
}

/// 真跑一遍：TCP 连接 + HTTP 取配置
class NetDiag {
  /// 与 ApiClient 保持同一套主机/端口，避免两边结论不一致
  ///
  /// [tcpTimeout] 可调的原因（v2.1.66）：首次启动的权限引导页里，这一次连接
  /// **就是** iOS 弹出「是否允许使用无线数据」系统框的钩子。弹窗是模态的，
  /// 用户不点，请求就一直挂在 `connect()` 里 —— 6 秒的默认值根本不够用户
  /// 看清弹窗再点「允许」，结果是用户刚点完，这边已经超时判成「网络不通」，
  /// 之后也不会自己恢复。引导页因此传 15 秒。
  /// 首页静默自检没有弹窗要等，仍然用 6 秒，免得升级用户白等。
  static Future<NetDiagResult> run({
    Duration tcpTimeout = const Duration(seconds: 6),
    Duration httpTimeout = const Duration(seconds: 8),
  }) async {
    final base = Uri.parse(ApiConfig.baseUrl);
    final host = base.host;
    final port = base.hasPort ? base.port : 80;

    // ── ① 纯 TCP：这一步失败就说明请求根本没离开手机
    final sw = Stopwatch()..start();
    var tcpOk = false;
    var tcpErr = '';
    Socket? sock;
    try {
      sock = await Socket.connect(host, port, timeout: tcpTimeout);
      tcpOk = true;
    } catch (e) {
      tcpErr = _brief(e);
    } finally {
      sw.stop();
      try {
        sock?.destroy();
      } catch (_) {}
    }
    final tcpMs = sw.elapsedMilliseconds;

    // ── ② HTTP：端口通不通都要试，方便看到「通但报错」
    final sw2 = Stopwatch()..start();
    var status = 0;
    var httpErr = '';
    try {
      final c = HttpClient()..connectionTimeout = httpTimeout;
      final req = await c.getUrl(
          Uri.parse('${ApiConfig.baseUrl}/index.php?r=/auth/config'));
      req.persistentConnection = false;
      final res = await req.close().timeout(httpTimeout);
      final body = await res
          .transform(const Utf8Decoder(allowMalformed: true))
          .join()
          .timeout(httpTimeout);
      status = res.statusCode;
      // 200 但正文不是 JSON（nginx 错误页）也要说清楚
      if (status == 200 && !body.trimLeft().startsWith('{')) {
        httpErr = '回包不是接口数据（前 40 字：${body.trim().substring(0, body.trim().length.clamp(0, 40))}）';
      }
      c.close(force: true);
    } catch (e) {
      httpErr = _brief(e);
    }
    sw2.stop();

    return NetDiagResult(
      tcpOk: tcpOk,
      tcpMs: tcpMs,
      tcpError: tcpErr,
      httpStatus: httpErr.isEmpty ? status : 0,
      httpMs: sw2.elapsedMilliseconds,
      httpError: httpErr,
    );
  }

  static String _brief(Object e) {
    if (e is SocketException) {
      final m = e.message.trim();
      final os = e.osError?.message ?? '';
      return 'SocketException: ${m.isEmpty ? os : m}${os.isEmpty || m.contains(os) ? '' : ' / $os'}';
    }
    if (e is TimeoutException) return 'TimeoutException: 等待超时';
    if (e is HttpException) return 'HttpException: ${e.message}';
    return '${e.runtimeType}: $e';
  }
}
