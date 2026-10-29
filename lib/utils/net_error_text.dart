import '../services/api_client.dart';

/// 一次失败的「人话解释」
class ErrorText {
  /// 给用户看的一句话（toast 里就是它）
  final String text;

  /// 底层真实原因，排查用。null = 这不是网络问题
  final String? detail;

  /// 是不是「重试一下可能就好了」的网络故障
  final bool isNet;

  const ErrorText(this.text, {this.detail, this.isNet = false});
}

/// 把登录/注册链路上抛出的异常翻译成用户能看懂、且**不误导**的一句话。
///
/// 抽成纯函数是为了能单测 —— 这段逻辑历史上出过两次事故：
///
///   1. 老实现用 `s.contains('Connection')` 判断网络。`Connection` 这个词
///      太常见：`HttpException: Connection closed before full header was
///      received`（App 切后台后复用了被系统回收的空闲连接）明明只是
///      「回包断了、重试就好」，却被说成「连不上服务器」。用户照着提示
///      换 WiFi、切流量、重启手机，全白折腾。
///   2. 后端返回的业务错误（「验证码错了」「今天次数用完了」）如果被
///      吞成网络问题，用户永远不知道该改什么。
///
/// 现在的规则：
///   · [ApiNetException] → 按 connect / timeout / broken 分三种说法，标记 isNet
///   · [ApiException]    → 服务器说话了就原样转达，不标 isNet
///   · 其它              → 去掉 `Exception:` 前缀，兜底「操作失败」
ErrorText describeError(Object e) {
  // 先把 SocketException / HttpException / TimeoutException 以及已经被
  // ApiClient 包好的 ApiNetException 统一归一，再按三种故障给说法。
  // 这样「什么算网络问题」只有一处定义（api_client 的 asNetError），
  // 不会像以前那样在界面层再写一遍 contains('Connection') 各说各话。
  final net = ApiClient.asNetError(e);
  if (net != null) {
    switch (net.kind) {
      case 'timeout':
        return ErrorText('服务器响应超时了，请重试',
            detail: net.detail, isNet: true);
      case 'broken':
        return ErrorText('网络连接被中断，请再试一次',
            detail: net.detail, isNet: true);
      default:
        return ErrorText('连不上服务器，请检查网络后重试',
            detail: net.detail, isNet: true);
    }
  }

  if (e is ApiException) {
    return ErrorText(
      e.message.trim().isEmpty ? '操作失败，请稍后重试' : e.message,
    );
  }

  var s = e.toString().trim();
  // ★ 只能剥掉**开头**的类名前缀。
  //   不能用 replaceAll('Exception: ')：`SocketException: xxx` 里也含
  //   `Exception: `，会被剥成 `SocketConnection refused…`，
  //   「SocketException」这个关键词随之消失，兜底判断就失效了（实测踩过）。
  s = s.replaceFirst(RegExp(r'^(ApiException|Exception):\s*'), '');
  // 兜底：有些老代码直接抛 `Exception('SocketException: ...')`（不是真的
  // SocketException 类型），上面按类型判断抓不到，只能在字符串上再兜一次。
  if (RegExp(
    r'SocketException|Connection refused|Connection timed out|'
    r'Failed host lookup|Network is unreachable',
    caseSensitive: false,
  ).hasMatch(s)) {
    return ErrorText('连不上服务器，请检查网络后重试', detail: s, isNet: true);
  }
  return ErrorText(s.isEmpty ? '操作失败，请稍后重试' : s);
}
