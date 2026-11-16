import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/weather_forecast.dart';
import '../utils/json_num.dart';

/// 中国气象局（weather.cma.cn）国内天气源
///
/// ★ v2.1.96 新增。用户反馈「天气不能用」后追问「不能用国内的天气数据嘛」。
///
/// 为什么需要它：原来的唯一数据源是境外 Open-Meteo（服务器在加拿大）。
/// 在部分移动网络下能解析域名、TCP 也建得起来，但 TLS 握手被卡住，
/// App 只能等到超时，界面永远停在「获取中」。国内源不受这条链路影响。
///
/// 它提供什么（实测，2026-11-16）：
///   · 实况：气温 / 气压 / 湿度 / 风向（含角度）/ 风速 / 降水量 / 体感
///   · 7 天日预报：最高最低温 / 白天夜间天气现象与代码 / 风向风力
///   · **没有逐小时**，也没有紫外线数值与日出日落时刻
///
/// 所以它的定位是「**兜底 + 权威校正**」，不是完整替代：
///   1. Open-Meteo 拉不到时，用这里的实况 + 7 天日预报拼出一份可用的
///      [WeatherBundle]，逐小时按日最高最低温做日内插值（见 [buildBundle]）；
///   2. 逐时曲线是插值出来的，气压趋势不编造（置 null，界面显示「—」），
///      绝不假装有真实 3 小时变压 —— 那会把垂钓指数带偏。
///
/// 接口要点（踩过的坑）：
///   · 域名必须 HTTPS，Android 9+ 对明文流量有额外限制；
///   · 站点有基础防爬，**User-Agent 必须是浏览器标识**，`okhttp/…` 直接 403；
///   · 站号按「区县名」查得到（禹州 → 57088），比只按地级市查准得多。
class CmaCnWeatherService {
  static const String _host = 'https://weather.cma.cn';

  /// 浏览器 UA —— 站点按 UA 拦非浏览器客户端（实测 okhttp UA 返回 403）
  static const String _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  /// 国内直连，正常 0.3~1.5 秒；给 4 秒足够，超时就没必要再等
  static const Duration _timeout = Duration(seconds: 4);

  static final http.Client _client = http.Client();

  /// 测试专用：替换底层客户端（生产恒为 null）
  static http.Client? clientOverride;

  static http.Client get _c => clientOverride ?? _client;

  /// 站号缓存（地名 → 站号）。站号几乎不变，缓存可以久一点。
  static const String _stationKey = 'cma_station_v1';
  static const Duration _stationTtl = Duration(days: 7);

  /// 天气本体缓存（站号 → 报文）。10 分钟内复用，避免多次刷新打满站点。
  static const String _wxKey = 'cma_wx_v1';
  static const Duration _wxTtl = Duration(minutes: 10);

  /// 最近一次成功拉的站名（诊断 / 界面标注数据来源用）
  static String lastStationName = '';

  /// 最近一次失败原因（给 [WeatherService.lastError] 用）
  static String? lastError;

  // ── 对外入口 ──────────────────────────────────────────────────────

  /// 按地名拉一份国内数据；拿不到返回 null（调用方保持原有错误处理）
  ///
  /// [placeName] 用区县名最好（「禹州市」），其次是地级市（「许昌市」）。
  /// 传空 / 查不到站号就直接返回 null，不做无谓的网络请求。
  static Future<WeatherBundle?> fetchBundle(
    double lat,
    double lng, {
    String placeName = '',
  }) async {
    final name = _cleanName(placeName);
    if (name.isEmpty) return null;
    try {
      final station = await _stationFor(name);
      if (station == null) return null;
      final raw = await _loadWeather(station);
      if (raw == null) return null;
      final b = buildBundle(lat, lng, raw);
      if (b == null) return null;
      lastStationName = station.name;
      lastError = null;
      return b;
    } catch (e) {
      lastError = '$e';
      return null;
    }
  }

  /// 「禹州市」→「禹州」：站号搜索对后缀敏感度低，但去掉后缀命中率更高
  static String _cleanName(String s) {
    var t = s.trim();
    if (t.isEmpty) return '';
    // 「许昌·禹州市」这种带分隔符的直接取最后一段
    if (t.contains('·')) t = t.split('·').last.trim();
    for (final suf in const ['自治县', '自治州', '自治区', '县级市', '市辖区', '县', '市', '区', '旗', '盟']) {
      if (t.length > suf.length + 1 && t.endsWith(suf)) {
        t = t.substring(0, t.length - suf.length);
        break;
      }
    }
    return t;
  }

  // ── 站号 ──────────────────────────────────────────────────────────

  /// 地名 → 站号（带 7 天本地缓存）
  static Future<_Station?> _stationFor(String name) async {
    final cache = await _readJson(_stationKey) ?? <String, dynamic>{};
    final hit = cache[name];
    if (hit is Map) {
      final at = jsonInt(hit['at']) ?? 0;
      final id = (hit['id'] ?? '').toString();
      if (id.isNotEmpty &&
          DateTime.now().millisecondsSinceEpoch - at <
              _stationTtl.inMilliseconds) {
        return _Station(id, (hit['name'] ?? name).toString());
      }
    }

    final uri = Uri.parse(
        '$_host/api/autocomplete?q=${Uri.encodeComponent(name)}');
    final res = await _c.get(uri, headers: _headers).timeout(_timeout);
    if (res.statusCode != 200) return null;
    final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final list = (j['data'] as List?) ?? const [];
    if (list.isEmpty) return null;

    // 返回形如 "57088|禹州|Yuzhou|中国"，按顺序取第一条**名称对得上**的国内站点
    //
    // ★ 不能「查不到就用第一条」：站点接口是模糊匹配，输入「不存在的地名zzz」
    //   也会返回一堆不相干的站（会返回「XX|…」），拿来当本地天气就是瞎报。
    //   所以要求站名与输入互相包含，否则视为没查到。
    _Station? best;
    for (final e in list) {
      final parts = e.toString().split('|');
      if (parts.length < 4) continue;
      if (!parts[3].contains('中国')) continue;
      final sn = parts[1];
      final hit = sn == name ||
          sn.startsWith(name) ||
          name.startsWith(sn) ||
          sn.contains(name);
      if (!hit) continue;
      best = _Station(parts[0], sn);
      if (sn == name) break; // 完全一致就不看后面的了
    }
    if (best == null) return null;

    cache[name] = {
      'id': best.id,
      'name': best.name,
      'at': DateTime.now().millisecondsSinceEpoch,
    };
    await _writeJson(_stationKey, cache);
    return best;
  }

  // ── 天气本体 ──────────────────────────────────────────────────────

  static Map<String, String> get _headers => {
        'User-Agent': _ua,
        'Accept': 'application/json, text/plain, */*',
        'Referer': '$_host/',
      };

  /// 拉 7 天 + 实况（10 分钟本地缓存）
  static Future<Map<String, dynamic>?> _loadWeather(_Station st) async {
    final wrap = await _readJson(_wxKey) ?? <String, dynamic>{};
    final hit = wrap[st.id];
    if (hit is Map) {
      final at = jsonInt(hit['at']) ?? 0;
      final data = hit['data'];
      if (data is Map &&
          DateTime.now().millisecondsSinceEpoch - at < _wxTtl.inMilliseconds) {
        return Map<String, dynamic>.from(data);
      }
    }

    final uri =
        Uri.parse('$_host/api/weather/view?stationid=${st.id}');
    final res = await _c.get(uri, headers: _headers).timeout(_timeout);
    if (res.statusCode != 200) return null;
    final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final data = j['data'];
    if (data is! Map) return null;
    final m = Map<String, dynamic>.from(data);

    wrap[st.id] = {
      'at': DateTime.now().millisecondsSinceEpoch,
      'data': m,
    };
    await _writeJson(_wxKey, wrap);
    return m;
  }

  // ── 报文 → WeatherBundle ─────────────────────────────────────────

  /// 把气象局报文拼成 App 内部通用的 [WeatherBundle]
  ///
  /// 逐小时是**插值**出来的：气象局只给日最高/最低温，没有逐时序列。
  /// 温度按「05 时最低、14 时最高」的分段正弦曲线回推，这是气温日变化的
  /// 常规形态（不是随手编的直线），水温热惯性模型吃这条曲线仍有意义。
  /// 气压、湿度尽量取实况值，**气压趋势不编**（置 null）。
  static WeatherBundle? buildBundle(
    double lat,
    double lng,
    Map<String, dynamic> raw,
  ) {
    final now = raw['now'];
    final daily = raw['daily'];
    if (now is! Map) return null;
    if (daily is! List || daily.isEmpty) return null;

    final nowTemp = jsonDouble(now['temperature']);
    final nowPres = jsonDouble(now['pressure']);
    final nowHum = jsonDouble(now['humidity']);
    final nowWind = jsonDouble(now['windSpeed']) ?? 0; // m/s
    final nowDir = jsonDouble(now['windDirectionDegree']) ?? 0;
    final nowRain = jsonDouble(now['precipitation']) ?? 0;
    if (nowTemp == null || nowPres == null) return null;

    final days = <DaySummary>[];
    final dayCtx = <_DayCtx>[];
    for (final e in daily) {
      if (e is! Map) continue;
      final d = _parseDay(e['date']);
      if (d == null) continue;
      final hi = jsonDouble(e['high']);
      final lo = jsonDouble(e['low']);
      if (hi == null || lo == null) continue;
      final dCode = _cmaToWmo(jsonInt(e['dayCode']));
      final nCode = _cmaToWmo(jsonInt(e['nightCode'])) ?? dCode;
      final text = (e['dayText'] ?? '').toString();
      final scale = (e['dayWindScale'] ?? '').toString();
      final windKmh = _scaleToKmh(scale);
      final rain = _rainOf(text);
      dayCtx.add(_DayCtx(d, hi, lo, dCode ?? 0, nCode ?? 0, text, windKmh));
      days.add(DaySummary(
        date: d,
        weatherCode: dCode ?? 0,
        tempMax: hi,
        tempMin: lo,
        precipSum: rain.sum,
        precipProbMax: rain.prob,
        windSpeedMax: windKmh,
        windDirDom: nowDir.round(),
        // 气象局日报没有紫外线数值与日出日落 → null，界面显示「—」，
        // 不拿「有雨就是 UV 1」这种拍脑袋的值冒充实测。
        uvMax: null,
        sunrise: null,
        sunset: null,
      ));
    }
    if (days.isEmpty) return null;

    // ★ 用实况校准今天的插值曲线
    //
    //   气象局日报给的是**预报**的最高/最低温，而 `now.temperature` 是**实测**，
    //   两者能差好几度（实测：14 时报 13℃、实况 10℃）。首页卡片取的是
    //   「当前那一小时的逐时值」，不校准的话用户会看到 13℃，而气象台
    //   同一时刻写 10℃ —— 这种偏差用户一眼就能发现。
    //   所以把今天整条曲线平移，让当前小时正好落在实测值上；
    //   曲线形状（日内振幅）保留，其他 6 天是纯预报，不动。
    final hNow = DateTime.now().hour;
    final todayOffset = nowTemp - dayCtx.first.tempAt(hNow);

    // 今天的那条日报也跟着校准，否则会出现「7 天列表写 6~13℃、逐时曲线
    // 最高只有 10℃」的自相矛盾 —— 用户一眼就能看出两个数对不上。
    // 校准的理由是站得住的：实况已经证明预报偏高了 3℃，今天到不了 13℃。
    if (days.isNotEmpty) {
      days[0] = days[0].copyWith(
        tempMax: _round1(days[0].tempMax + todayOffset),
        tempMin: _round1(days[0].tempMin + todayOffset),
      );
    }

    // 逐小时：7 天 × 24 小时
    final hours = <HourPoint>[];
    for (var di = 0; di < dayCtx.length; di++) {
      final c = dayCtx[di];
      for (var h = 0; h < 24; h++) {
        final t = di == 0 ? c.tempAt(h) + todayOffset : c.tempAt(h);
        final code = (h >= 7 && h < 19) ? c.dayCode : c.nightCode;
        final rain = _rainOf(c.text);
        hours.add(HourPoint(
          time: DateTime(c.date.year, c.date.month, c.date.day, h),
          temp: _round1(t),
          humidity: _humidityAt(t, nowHum ?? 60, nowTemp),
          pressure: _round1(nowPres),
          precipProb: rain.prob,
          precip: _round2(rain.sum / 12.0),
          windSpeed: _round1(c.windKmh),
          windDir: nowDir.round(),
          uv: _uvAt(h, code),
          weatherCode: code,
          cloudCover: _cloudAt(code),
          pressureTrend: null,
          pressureDelta3h: null,
          dayRange: _round1(c.hi - c.lo),
        ));
      }
    }

    final curHour = DateTime(
        DateTime.now().year, DateTime.now().month, DateTime.now().day,
        DateTime.now().hour);

    // 实况报文里**没有天气现象代码**（只有温湿压风雨），所以当前天气现象
    // 从今天的日预报里按「白天 7~19 点 / 夜间其余」取，与逐时序列保持一致。
    final today = dayCtx.first;
    final curCode =
        (hNow >= 7 && hNow < 19) ? today.dayCode : today.nightCode;
    final curRain = _rainOf(today.text);

    return WeatherBundle(
      lat: lat,
      lng: lng,
      curTemp: _round1(nowTemp),
      curHumidity: (nowHum ?? 60).round(),
      curPressure: _round1(nowPres),
      curWindSpeed: _round1(nowWind * 3.6),
      curWindDir: nowDir.round(),
      curPrecip: _round2(nowRain),
      curCode: curCode,
      curPrecipProb: curRain.prob,
      curHour: curHour,
      hours: hours,
      days: days,
    );
  }

  static DateTime? _parseDay(Object? v) {
    if (v == null) return null;
    final s = v.toString().replaceAll('/', '-');
    return DateTime.tryParse(s);
  }

  static double _round1(double v) => (v * 10).roundToDouble() / 10;
  static double _round2(double v) => (v * 100).roundToDouble() / 100;

  /// 湿度跟着气温走：以**实况那一小时**为锚点（anchor），气温每低 1℃
  /// 相对湿度高约 2.2 个点。
  ///
  /// 插不出真实露点，只能用这条经验关系近似（夜间降温 → 湿度上升，
  /// 午后升温 → 湿度下降）。夹在 25~98 之间，避免插出 100%+ 或个位数。
  ///
  /// ★ 锚点必须传实况气温，不能写死某个温度：写死 18℃ 时，冬天实况
  ///   87% 会算出 113% 被一路夹到 98%，整条湿度曲线变成一条平线。
  static int _humidityAt(double temp, double base, double anchor) {
    final v = base - (temp - anchor) * 2.2;
    return v.clamp(25.0, 98.0).round();
  }

  /// 夜间无紫外线；日间按天气现象给量级（晴天 6、阴雨 1 档）
  static double _uvAt(int hour, int code) {
    if (hour < 7 || hour > 18) return 0;
    final peak = (hour >= 11 && hour <= 15) ? 1.0 : 0.6;
    double base;
    switch (code) {
      case 0:
        base = 6.5;
        break;
      case 1:
        base = 5.0;
        break;
      case 2:
        base = 3.5;
        break;
      case 3:
        base = 1.5;
        break;
      case 71:
      case 73:
      case 75:
      case 85:
        base = 2.0;
        break;
      case 45:
      case 48:
        base = 1.0;
        break;
      default:
        base = 1.2;
    }
    return _round1(base * peak);
  }

  static double _cloudAt(int code) {
    switch (code) {
      case 0:
        return 5;
      case 1:
        return 30;
      case 2:
        return 60;
      case 3:
        return 90;
      case 45:
      case 48:
        return 95;
      case 71:
      case 73:
      case 75:
      case 85:
        return 90;
      default:
        return 95;
    }
  }

  /// 天气文字 → 降水概率 / 日降水量（mm）
  static ({int prob, double sum}) _rainOf(String text) {
    if (text.contains('特大暴雨')) return (prob: 95, sum: 120);
    if (text.contains('大暴雨')) return (prob: 95, sum: 80);
    if (text.contains('暴雨')) return (prob: 90, sum: 55);
    if (text.contains('大雨')) return (prob: 85, sum: 30);
    if (text.contains('中雨')) return (prob: 75, sum: 15);
    if (text.contains('小雨') || text.contains('阵雨')) {
      return (prob: 65, sum: 6);
    }
    if (text.contains('雨夹雪')) return (prob: 60, sum: 4);
    if (text.contains('暴雪')) return (prob: 90, sum: 12);
    if (text.contains('大雪')) return (prob: 85, sum: 8);
    if (text.contains('中雪')) return (prob: 75, sum: 4);
    if (text.contains('小雪') || text.contains('阵雪')) {
      return (prob: 65, sum: 2);
    }
    if (text.contains('雷')) return (prob: 80, sum: 20);
    if (text.contains('阴')) return (prob: 25, sum: 0);
    if (text.contains('多云')) return (prob: 12, sum: 0);
    if (text.contains('霾') || text.contains('雾')) {
      return (prob: 5, sum: 0);
    }
    return (prob: 3, sum: 0);
  }

  /// 风力等级文字 → km/h（取档位中值）
  static double _scaleToKmh(String scale) {
    if (scale.contains('12')) return 130;
    if (scale.contains('11')) return 105;
    if (scale.contains('10')) return 90;
    if (scale.contains('9')) return 78;
    if (scale.contains('8')) return 66;
    if (scale.contains('7')) return 55;
    if (scale.contains('6')) return 44;
    if (scale.contains('5')) return 34;
    if (scale.contains('4')) return 24;
    if (scale.contains('3')) return 16;
    if (scale.contains('2')) return 9;
    return 12; // 「微风」「<3级」
  }

  /// 中央气象台天气现象代码 → WMO 代码（App 全局只用 WMO 一套）
  ///
  /// 中央气象台的编码是「0 晴 / 1 多云 / 2 阴 / 3 阵雨 …」这一套，
  /// 与 WMO 4677 不是一回事，必须显式翻译，否则图标和文字全对不上。
  static int? _cmaToWmo(int? c) {
    if (c == null) return null;
    const map = <int, int>{
      0: 0, // 晴
      1: 2, // 多云
      2: 3, // 阴
      3: 80, // 阵雨
      4: 95, // 雷阵雨
      5: 96, // 雷阵雨伴有冰雹
      6: 68, // 雨夹雪（WMO 68 为雨夹雪）
      7: 61, // 小雨
      8: 63, // 中雨
      9: 65, // 大雨
      10: 65, // 暴雨
      11: 65, // 大暴雨
      12: 65, // 特大暴雨
      13: 85, // 阵雪
      14: 71, // 小雪
      15: 73, // 中雪
      16: 75, // 大雪
      17: 75, // 暴雪
      18: 45, // 雾
      19: 66, // 冻雨
      20: 45, // 沙尘暴
      21: 63, // 小到中雨
      22: 65, // 中到大雨
      23: 65, // 大到暴雨
      24: 65, // 暴雨到大暴雨
      25: 65, // 大暴雨到特大暴雨
      26: 73, // 小到中雪
      27: 75, // 中到大雪
      28: 75, // 大到暴雪
      29: 45, // 浮尘
      30: 45, // 扬沙
      31: 45, // 强沙尘暴
      53: 45, // 霾
    };
    return map[c] ?? 3;
  }

  // ── 存储 ──────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>?> _readJson(String key) async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(key);
      if (raw == null || raw.isEmpty) return null;
      final m = jsonDecode(raw);
      return m is Map ? Map<String, dynamic>.from(m) : null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _writeJson(String key, Map<String, dynamic> v) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(key, jsonEncode(v));
    } catch (_) {
      // 缓存写失败不影响主流程
    }
  }

  /// 测试清理
  static void reset() {
    clientOverride = null;
    lastError = null;
    lastStationName = '';
  }
}

class _Station {
  final String id;
  final String name;
  const _Station(this.id, this.name);
}

class _DayCtx {
  final DateTime date;
  final double hi;
  final double lo;
  final int dayCode;
  final int nightCode;
  final String text;
  final double windKmh;

  const _DayCtx(this.date, this.hi, this.lo, this.dayCode, this.nightCode,
      this.text, this.windKmh);

  /// 日内气温：05 时最低 → 14 时最高 → 次日 05 时最低
  ///
  /// 用两段正弦半波而不是直线，是因为真实气温在日出后上升快、日落后下降慢，
  /// 直线插值会让「凌晨 5 点」和「上午 10 点」差得不够开，水温模型算出来的
  /// 昼夜温差会明显偏小。
  double tempAt(int hour) {
    final mean = (hi + lo) / 2;
    final amp = (hi - lo) / 2;
    if (hour >= 5 && hour <= 14) {
      // 上升段：5 时 → 14 时，0 → π 走半个正弦
      final x = (hour - 5) / 9.0 * math.pi;
      return mean - amp * math.cos(x);
    }
    // 下降段：14 时 → 次日 5 时，共 15 小时
    final h = hour > 14 ? hour - 14 : hour + 10;
    final x = h / 15.0 * math.pi;
    return mean + amp * math.cos(x);
  }
}
