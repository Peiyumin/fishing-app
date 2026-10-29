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
///   · [ApiNetException] → 按 connect / timeout / broken 分类，且 connect
///     还要按**系统给的真实错误**再细分（超时 / 无网络 / 被拒绝）——
///     同样是「连不上」，用户的下一步动作完全不同：
///       超时   → 换个网络（多半是这个端口被限了）
///       无网络 → 去开移动数据 / 检查是否禁止本 App 使用无线数据
///   · [ApiException]    → 服务器说话了就原样转达，不标 isNet
///   · 其它              → 去掉 `Exception:` 前缀，兜底「操作失败」
ErrorText describeError(Object e) {
  // 先把 SocketException / HttpException / TimeoutException 以及已经被
  // ApiClient 包好的 ApiNetException 统一归一，再按故障类型给说法。
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
        return ErrorText(connectText(net.detail),
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
    r'Failed host lookup|Network is unreachable|No route to host',
    caseSensitive: false,
  ).hasMatch(s)) {
    return ErrorText(connectText(s), detail: s, isNet: true);
  }
  return ErrorText(s.isEmpty ? '操作失败，请稍后重试' : s);
}

/// 「根本没连上」再细分一层。
///
/// [detail] 是系统给的原始错误（`SocketException: ...` 那一串）。
/// **必须按真实错误说话**：这三种情况用户要做的事完全不同，全都写成
/// 「连不上服务器，请检查网络」等于什么都没说 —— 用户只会反复开关 WiFi。
String connectText(String detail) {
  final d = detail.toLowerCase();
  // 连接超时：SYN 发出去没有回应。手机流量/某些 WiFi 会拦非标准端口
  // （本站 API 在 8801），浏览器能开不代表 App 能连。
  if (d.contains('timed out') || d.contains('timeout')) {
    return '连接服务器超时，请换一个网络再试（WiFi 与移动数据互换）';
  }
  // 压根没有出口：飞行模式、移动数据关、或系统禁止了本 App 使用无线数据
  if (d.contains('unreachable') || d.contains('no route')) {
    return '手机当前没有可用网络，请检查移动数据或 WiFi';
  }
  // 域名解析失败（现在直连 IP 不会出现，换域名后要能看懂）
  if (d.contains('failed host lookup') || d.contains('name or service')) {
    return '服务器地址解析失败，请稍后重试';
  }
  // 端口没人监听 / 被防火墙 RST
  if (d.contains('refused')) {
    return '服务器暂时无法连接，请稍后重试';
  }
  // 断网瞬间、权限被拒（如 iOS 关闭了本 App 的无线数据）也常走这里
  if (d.contains('permission denied')) {
    return '系统禁止了本 App 联网，请到手机设置里允许它使用无线数据';
  }
  return '连不上服务器，请检查手机网络后重试';
}
