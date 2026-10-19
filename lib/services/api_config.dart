/// 自建后端 API 配置
///
/// 当前对接：PHP 管理后台自带的 API 层（api/index.php）
/// 地址格式：http(s)://你的域名(或IP):端口 + /api
///   例：http://106.54.193.199:8801/api
/// 注意：不含尾部斜杠；PHP 后台装在子目录时要把子目录加上，如
///   http://你的域名/fishing_admin/api
///
/// baseUrl 为空或占位时，App 自动进入「演示模式」：
/// 使用内置示例数据浏览，发布/点赞/报错仅在本地预览。
class ApiConfig {
  /// 后端接口根地址（以 /api 结尾，无尾部斜杠）
  static const String baseUrl = 'http://106.54.193.199:8801/api';

  /// 后端是否可用（决定走真实接口还是演示模式）
  static bool get enabled => baseUrl.isNotEmpty && !baseUrl.contains('PLACEHOLDER');

  /// 站点根地址：去掉 /api 后缀，保留 协议+主机+端口
  /// 例：http://106.54.193.199:8801
  static String get origin {
    final u = Uri.parse(baseUrl);
    final port = u.hasPort ? ':${u.port}' : '';
    return '${u.scheme}://${u.host}$port';
  }

  /// 把后端返回的图片/视频地址修正为「App 真的能访问」的地址
  ///
  /// 为什么需要它：
  /// 生成后台部署在宝塔 + 反代环境时，PHP 的 HTTP_HOST 常常只剩域名/IP，
  /// 端口被丢掉 —— 接口会返回 `http://106.54.193.199/uploads/xx.png`
  /// （少了 :8801），App 请求时 404，发布出来的图和启动页图就全白了。
  ///
  /// 规则：
  ///   1. 空值 → null（调用方自行降级为占位图）
  ///   2. `//host/path` 形式 → 补上 baseUrl 的协议
  ///   3. 相对路径 `/uploads/x.png` → 拼上站点根地址
  ///   4. 绝对地址且与 baseUrl 同主机（含少了端口的情况）→ 用 baseUrl 的
  ///      协议/主机/端口整体重写，只保留路径与查询串
  ///   5. 其他外链（CDN、图床）→ 原样返回
  static String? mediaUrl(String? raw) {
    if (raw == null) return null;
    var s = raw.trim();
    if (s.isEmpty) return null;

    final base = Uri.parse(baseUrl);

    if (s.startsWith('//')) s = '${base.scheme}:$s';

    if (!s.toLowerCase().startsWith('http')) {
      return s.startsWith('/') ? '$origin$s' : '$origin/$s';
    }

    final u = Uri.tryParse(s);
    if (u == null || u.host.isEmpty) return s;
    if (u.host != base.host) return s; // 外链不动

    final path = u.path.isEmpty ? '' : u.path;
    final query = u.hasQuery ? '?${u.query}' : '';
    return '$origin$path$query';
  }

  /// 批量修正图片地址列表（自动丢弃空值）
  static List<String> mediaList(dynamic raw) {
    if (raw is! List) return const [];
    final out = <String>[];
    for (final e in raw) {
      final v = mediaUrl(e?.toString());
      if (v != null && v.isNotEmpty) out.add(v);
    }
    return out;
  }
}
