/// 宽容数值解析：接口里的「数字」不一定是 num。
///
/// ★★ 为什么必须有这个文件（v2.1.50 修的线上事故）
///
/// 后端 PHP 用 PDO 读 MySQL，DECIMAL / BIGINT 列默认**以字符串返回**
/// （`PDO::ATTR_STRINGIFY_FETCHES` 默认 true，且预处理模拟模式下列类型全是
/// string）。`json_encode` 原样输出，于是接口里出现：
///
/// ```json
/// {"length_cm": "1000.00", "weight_g": "1050.0"}
/// ```
///
/// 客户端只要有 `(json['length_cm'] as num?)?.toDouble()` 这种写法，就会抛
///
/// ```
/// type 'String' is not a subtype of type 'num?' in type cast
/// ```
///
/// 它是**运行时类型错误**，会顺着 `Post.fromJson` 冒到 `fetchFeed` 的 catch，
/// 结果首页、渔获页、发现页、详情页**整页加载失败**——一条带尺寸的鱼获就足以
/// 让全站信息流打不开。这类崩溃没有任何前缀可循，用户只能看到「加载失败」。
///
/// 所以：**任何来自网络 JSON 的数值，一律走这里的函数，禁止裸 `as num`。**
/// 后端也在 v39 顺手把该转的字段转了类型，但客户端不能依赖后端守规矩 ——
/// 老版本接口、第三方接口（Open-Meteo）、历史缓存都得能读。
library;

/// 从任意值里尽量取出 num。
///
/// * `num` / `bool` 直接认
/// * `String` 走 `num.tryParse`，并容忍这些「看起来像数字」的脏数据：
///   - 前后空白、全角空格
///   - 千分位逗号 `"1,050.0"`
///   - 正号 `"+3"`
///   - 尾部单位 `"1050 g"`、`"25cm"`
/// * 取不到返回 `null`（调用方自己决定兜底值，绝不抛异常）
num? jsonNum(dynamic v) {
  if (v == null) return null;
  if (v is num) return v;
  if (v is bool) return v ? 1 : 0;
  if (v is String) {
    var s = v.trim();
    if (s.isEmpty) return null;
    final direct = num.tryParse(s);
    if (direct != null) return direct;
    // 脏数据清洗：去千分位、去全角空格、去正号
    s = s.replaceAll(',', '').replaceAll('\u00A0', '').replaceAll(' ', '');
    if (s.startsWith('+')) s = s.substring(1);
    final cleaned = num.tryParse(s);
    if (cleaned != null) return cleaned;
    // 带单位的「1050 g」「25cm」：取出开头那段数字
    final m = RegExp(r'^-?\d+(\.\d+)?').firstMatch(s);
    if (m != null) return num.tryParse(m.group(0)!);
    return null;
  }
  // 极少数接口会把数字塞进 List（如 [34.1]）或 Map，尽力取第一个
  if (v is List && v.isNotEmpty) return jsonNum(v.first);
  return null;
}

/// 转 double；取不到返回 [fallback]
double? jsonDouble(dynamic v, [double? fallback]) => jsonNum(v)?.toDouble() ?? fallback;

/// 转 int；`"1000.00"` 会得到 1000（截断，不四舍五入）
int? jsonInt(dynamic v, [int? fallback]) => jsonNum(v)?.toInt() ?? fallback;

/// 转 int，取不到用 0（最常见的兜底写法）
int jsonIntOrZero(dynamic v) => jsonNum(v)?.toInt() ?? 0;

/// 宽容时间解析：换掉 `DateTime.parse(x as String)`。
///
/// `DateTime.parse` 对格式极度挑剔，而且 **null 直接抛 NoSuchMethod、
/// 空串/`"0000-00-00"`/`"2026/10/28"` 抛 FormatException**。这些异常都发生在
/// 模型构造函数里，一旦有一条脏数据，整页列表就全废 —— 和上面 length_cm 那条
/// 是同一类事故。后端 `created_at` 换过一次格式（带 Z 的 UTC），历史数据里
/// 还有 MySQL 的 `0000-00-00 00:00:00`，所以必须容错。
///
/// 支持：
/// * ISO8601（带 Z / 带毫秒 / 带时区偏移）
/// * `2026-10-28 11:52:35`（空格分隔）
/// * `2026/10/28 11:52`
/// * 秒级 / 毫秒级时间戳（10 位 / 13 位数字）
/// * `DateTime` / 其它类型 → 走 `toString()`
DateTime? jsonDate(dynamic v, {DateTime? fallback}) {
  if (v == null) return fallback;
  if (v is DateTime) return v;

  // 时间戳（秒 / 毫秒）—— 后端偶尔直接给 int
  final n = v is num ? v : (v is String ? num.tryParse(v.trim()) : null);
  if (n != null && n is num) {
    final i = n.toInt();
    if (i > 1000000000000) {
      return DateTime.fromMillisecondsSinceEpoch(i); // 13 位，毫秒
    }
    if (i > 1000000000) {
      return DateTime.fromMillisecondsSinceEpoch(i * 1000); // 10 位，秒
    }
  }

  var s = v.toString().trim();
  if (s.isEmpty) return fallback;
  // MySQL 的零值日期 / 明显无效的串
  if (s.startsWith('0000-00-00')) return fallback;

  final direct = DateTime.tryParse(s);
  if (direct != null) return direct;
  // `2026/10/28`、`2026年10月28日` 这类非 ISO 分隔符
  final alt = s
      .replaceAll('/', '-')
      .replaceAll('年', '-')
      .replaceAll('月', '-')
      .replaceAll('日', ' ')
      .trim();
  final asAlt = DateTime.tryParse(alt);
  if (asAlt != null) return asAlt;
  // 只有日期没时间（`2026-10-28`）+ 中文后缀等，再兜一次
  final m = RegExp(r'(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(alt);
  if (m != null) {
    return DateTime.tryParse(
        '${m.group(1)}-${m.group(2)!.padLeft(2, '0')}-${m.group(3)!.padLeft(2, '0')}');
  }
  return fallback;
}

/// `created_at` 这类「必须有值」的字段：解析不出来就用当前时间，
/// 保证模型永远能构造出来（列表不会因为一条脏数据整页打不开）。
DateTime jsonDateOrNow(dynamic v) => jsonDate(v) ?? DateTime.now();

/// 宽容列表：接口该给 `[]` 的时候有可能给 `{}`。
///
/// ★ 后端为了让「空对象」序列化成 `{}` 而不是 `[]`（PHP 的 `json_encode([])`
///   会得到 `[]`，空 Map 要 `(object)[]`），个别路由干脆统一返回对象。
///   客户端 `ApiClient.get('/posts') as List` 一旦碰上 `{}`，就抛
///   `type '_Map<String, dynamic>' is not a subtype of type 'List<dynamic>'`
///   —— 又是整页加载失败，报错文案还是英文。
///
/// 现在统一走这里：不是 List 就当空列表，页面显示「暂无数据」而不是崩。
List<dynamic> jsonList(dynamic v) {
  if (v is List) return v;
  if (v is Map) {
    // 常见包装：{list: []} / {items: []} / {rows: []} / {data: []}
    for (final k in const ['list', 'items', 'rows', 'data', 'records']) {
      final inner = v[k];
      if (inner is List) return inner;
    }
  }
  return const [];
}

/// 宽容对象：该给 `{}` 的时候有可能给 `[]` 或 null
Map<String, dynamic> jsonMap(dynamic v) {
  if (v is Map) return Map<String, dynamic>.from(v);
  return <String, dynamic>{};
}

/// 宽容布尔：后端同一个语义，有时给 `true/false`，有时给 `1/0`。
///
/// ★ `(json['isFollowing'] as bool?) ?? false` 遇到 `1` 会**静默变成 false** ——
///   不报错、不崩溃，但界面显示「未关注」「未签到」「会员未生效」，
///   用户会以为功能坏了（重装、清缓存、反复点），排查成本比崩溃还高。
///   这类「静默错」是本项目历史上被反馈最多的一类问题，统一走这里。
bool jsonBool(dynamic v, {bool fallback = false}) {
  if (v == null) return fallback;
  if (v is bool) return v;
  if (v is num) return v != 0;
  final s = v.toString().trim().toLowerCase();
  if (s.isEmpty) return fallback;
  if (s == '0' || s == 'false' || s == 'no' || s == 'off' || s == 'null') {
    return false;
  }
  return s == '1' || s == 'true' || s == 'yes' || s == 'on' || s == 'y';
}
