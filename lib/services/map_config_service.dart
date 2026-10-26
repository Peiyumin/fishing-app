import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_client.dart';
import '../services/api_config.dart';
import 'map_tile_source.dart';
import 'tile_health.dart';

/// 地图底图配置服务（v2.1.10 起，v2.2.0 增加星图地球）
///
/// ------------------------------------------------------------
/// 后台「系统设置 → 地图底图」里配置：
///   - geovisearth_token：星图地球 token（推荐，注册即用）
///   - tianditu_tk     ：天地图 tk（2026-10-01 起需授权，一般填不了）
///   - prefer          ：优先级 auto / geovisearth / tianditu / gaode
///
/// App 拉 GET /app/map-config 决定用哪家底图；
/// 全部拿不到时自动回退到免 key 的高德卫星图，
/// 保证「地图永远能打开」，不会因为一个密钥没配就白屏。
class MapConfigService {
  MapConfigService._();

  static String _geoToken = '';
  static String _tk = '';
  static String _prefer = 'auto';
  static String _engine = 'gl';
  static bool _loaded = false;

  /// 内置兜底的星图地球 token
  ///
  /// ★ 为什么要在包里放一份：用户报「WiFi 下野钓钓点地图不加载，只看到高德
  ///   底图」—— 底图源是 `/app/map-config` 决定的，而这个接口跑在
  ///   `http://106.54.193.199:8801`（非标准端口）。某些 WiFi（公司网、酒店网、
  ///   带端口过滤的路由器）会把这条链路掐掉：接口拿不到 → 没有 token →
  ///   退回免 key 高德 → 瓦片域名再被拦就整页空白。
  ///   把自家 token 作为最后一次兜底，至少「接口挂但图片域名通」的网络里，
  ///   地图仍然是星图。
  ///
  /// 这是**我们自己的** token（每个 App 请求里本来就能看到），不是竞品的；
  /// 后台配置一旦拿到就会覆盖它。
  static const String _kBundledGeoToken =
      '61cbccdaf687883052f53bf9bc1d6a9f5375037fcd0c8b3efd479288737bb0a5';

  /// 线路自检的临场覆盖（null = 用后台配置的优先级）
  static TileSourceKind? _kindOverride;

  /// 自检结论，给页面提示用（空串 = 一切正常）
  static String _healthNote = '';
  static bool _healthChecked = false;

  /// 最近一次自检的逐家结果（诊断面板展示）
  static List<TileHealthResult> lastProbe = const [];

  /// 自检结论：正常时为空串
  static String get healthNote => _healthNote;

  /// 本次会话是否已经自检过
  static bool get healthChecked => _healthChecked;

  /// 跑一遍线路自检，按顺序挑第一家能出图的底图
  ///
  /// 为什么必须**建图前**做：MapLibre 的 raster source 一旦建好就改不了
  /// 瓦片地址（0.22.0 的 controller 没有 setStyle），事后发现某家不通
  /// 只能整张图重建。事先探一张固定 z5 瓦片最省事。
  static Future<void> checkReachable({bool force = false}) async {
    if (_healthChecked && !force) return;
    _healthChecked = true;
    final order = candidates;
    if (order.isEmpty) return;

    final first = order.first;
    final results = <TileHealthResult>[];
    // 超时不能太长：这段等待是「建图前的灰屏」，宁可判错也不能让用户干等
    final r0 = await TileHealth.probe(first,
        timeout: const Duration(milliseconds: 2000));
    results.add(r0);
    if (r0.ok) {
      _kindOverride = null;
      _healthNote = '';
      lastProbe = results;
      return;
    }
    // 首选不通 → 顺着候选往下找第一家通的
    for (final src in order.skip(1)) {
      final r = await TileHealth.probe(src,
          timeout: const Duration(milliseconds: 1500));
      results.add(r);
      if (r.ok) {
        _kindOverride = src.kind;
        _healthNote =
            '${first.shortName} 在这条网络上打不开瓦片（${r0.detail}），'
            '已自动切到${src.shortName}';
        lastProbe = results;
        return;
      }
    }
    // 全都不通：保留首选（多半是整条网络的路由/DNS 问题，界面会提示）
    _kindOverride = null;
    _healthNote = '底图瓦片在这条网络上全部打不开（${r0.detail}），'
        '可能是网络拦截了地图图片域名';
    lastProbe = results;
  }

  /// 顶部「网络自检」按钮用：强制重跑一遍，把逐家结果显示出来
  static Future<List<TileHealthResult>> runDiagnostics() async {
    final order = candidates;
    final results = await TileHealth.probeAll(order);
    lastProbe = results;
    // 结论同步更新（下次建图就用新的选择）
    final ok = results.where((r) => r.ok).toList();
    if (ok.isNotEmpty) {
      final best = results.firstWhere((r) => r.ok);
      final idx = results.indexOf(best);
      _kindOverride = idx == 0 ? null : order[idx].kind;
      _healthNote = idx == 0 ? '' : '${order[0].shortName} 不通，已切到${order[idx].shortName}';
    } else {
      _healthNote = '底图瓦片在这条网络上全部打不开，可能是网络拦截了地图图片域名';
    }
    _healthChecked = true;
    return results;
  }

  /// 清掉自检结论（换网络后想重新判断时用）
  static void resetHealth() {
    _healthChecked = false;
    _kindOverride = null;
    _healthNote = '';
    lastProbe = const [];
  }

  /// 天地图密钥（空 = 不可用）
  static String get tiandituTk => _tk;

  /// 星图地球 token（空 = 不可用）
  static String get geovisearthToken =>
      _geoToken.isNotEmpty ? _geoToken : _kBundledGeoToken;

  /// 是否已拿到天地图密钥
  static bool get hasTianditu => _tk.isNotEmpty;

  /// 是否已拿到星图地球 token
  static bool get hasGeovisearth =>
      _geoToken.isNotEmpty || _kBundledGeoToken.isNotEmpty;

  /// 渲染内核：'gl' = MapLibre 原生（默认，快） / 'dart' = flutter_map（老内核兜底）
  static String get engine => _engine;

  /// 是否用原生 GL 内核
  ///
  /// 只有 Android / iOS 才有 MapLibre 原生实现；桌面端、Web、以及
  /// flutter test 的宿主环境一律走老的 flutter_map，避免平台通道缺失。
  static bool get useNativeEngine {
    if (_engine == 'dart' || kIsWeb) return false;
    return Platform.isAndroid || Platform.isIOS;
  }

  static TileSource _src(TileSourceKind k) => TileSource(
        kind: k,
        tk: _tk,
        geoToken: geovisearthToken,
      );

  /// 按优先级排好的候选底图（只含可用的）
  static List<TileSource> get candidates {
    final order = <TileSourceKind>[];
    switch (_prefer) {
      case 'gaode':
        order.add(TileSourceKind.gaode);
        break;
      case 'geovisearth':
        if (hasGeovisearth) order.add(TileSourceKind.geovisearth);
        break;
      case 'tianditu':
        if (hasTianditu) order.add(TileSourceKind.tianditu);
        break;
      default:
        break;
    }
    for (final k in const [
      TileSourceKind.geovisearth,
      TileSourceKind.tianditu,
      TileSourceKind.gaode,
    ]) {
      if (!order.contains(k)) order.add(k);
    }
    return order.map(_src).where((s) => s.usable).toList();
  }

  /// 实际应使用的底图
  ///
  /// 规则：
  ///   prefer 明确指定且对应密钥存在 → 用它
  ///   prefer=gaode              → 高德
  ///   其余（auto / 指定但没密钥）→ 星图地球 > 天地图 > 高德
  ///
  /// 星图地球排在最前，是因为天地图自 2026-10-01 起接口改为
  /// 「授权后调用」，个人自注册已拿不到可用的 tk。
  ///
  /// ★ `_kindOverride` 是**线路自检**的结果：如果首选那家在当前网络出不了图
  ///   （WiFi 拦截图片域名是真实存在的情况），就临场换一家，不用等用户报障。
  static TileSourceKind get preferredKind {
    final o = _kindOverride;
    if (o != null) {
      final s = _src(o);
      if (s.usable) return o;
    }
    switch (_prefer) {
      case 'gaode':
        return TileSourceKind.gaode;
      case 'geovisearth':
        if (hasGeovisearth) return TileSourceKind.geovisearth;
        break;
      case 'tianditu':
        if (hasTianditu) return TileSourceKind.tianditu;
        break;
      default:
        break;
    }
    if (hasGeovisearth) return TileSourceKind.geovisearth;
    if (hasTianditu) return TileSourceKind.tianditu;
    return TileSourceKind.gaode;
  }

  /// 当前底图（已把密钥装好，可直接给 flutter_map 用）
  static TileSource get source => TileSource(
        kind: preferredKind,
        tk: _tk,
        // 后台配置 / 本机缓存都空时用包内兜底 token
        geoToken: _geoToken.isNotEmpty ? _geoToken : _kBundledGeoToken,
      );

  /// 拉取配置（幂等，只拉一次）
  ///
  /// ★★ v2.1.27 修了两件事：
  ///
  /// ① **并发调用共享同一个请求**。以前是 `if (_loaded) return;`，而 `_loaded`
  ///    表示「已经开始了」而不是「已经完成」—— 第二个调用方会立刻拿到一个
  ///    已完成的 Future，此时配置还没回来，它读到的 `MapConfigService.source`
  ///    是兜底的高德。钓点页 initState 先调一次、地图页 initState 又调一次，
  ///    几乎必然踩中，结果就是「配了星图却用高德」。
  ///
  /// ② **不让建图等网络**，见 [_restoreCache] 注释。
  static Future<void>? _inflight;

  static Future<void> load({bool force = false}) {
    if (force) return _inflight = _doLoad(force: true);
    // 有请求在路上 → 等同一个 Future。**必须先判 _inflight 再判 _loaded**：
    // _loaded 在请求发出瞬间就为 true，此时配置还没回来。
    final f = _inflight;
    if (f != null) return f;
    if (_loaded) return Future.value();
    return _inflight = _doLoad();
  }

  static Future<void> _doLoad({bool force = false}) async {
    _loaded = true;
    final hasCache = await _restoreCache();
    if (!ApiConfig.enabled) return;
    if (hasCache && !force) {
      unawaited(_refresh()); // 后台刷新，不阻塞建图
    } else {
      await _refresh();
    }
    // 建图前先确认「当前网络到底能不能拉到底图瓦片」：
    // WiFi 拦截图片域名时，这一步会把底图换成能用的那家，
    // 而不是让用户对着空白地图猜。
    await checkReachable();
  }

  static Future<void> _refresh() async {
    try {
      // ApiClient 已自动拆出后端的 data 字段
      final cfg = await ApiClient.get('/app/map-config')
          .timeout(const Duration(seconds: 5)) as Map?;
      if (cfg != null) {
        _geoToken = (cfg['geovisearthToken'] ?? '').toString().trim();
        _tk = (cfg['tiandituTk'] ?? '').toString().trim();
        _prefer = (cfg['prefer'] ?? 'auto').toString().trim().toLowerCase();
        final e = (cfg['engine'] ?? 'gl').toString().trim().toLowerCase();
        _engine = e == 'dart' ? 'dart' : 'gl';
        await _saveCache();
      }
    } catch (_) {
      // 后台不可达：保持当前配置（缓存或高德兜底）
    }
  }

  /// 上次成功拿到的配置（本机缓存）
  ///
  /// 缓存的意义不是「省一次请求」，而是**不让建图等网络**：
  /// 底图源（星图 token / 天地图 tk / 用哪套内核）必须建图前就知道，
  /// 没有缓存时这部分延迟全落在用户盯灰屏的时间上。
  static const _kCacheKey = 'map_config_v1';

  static Future<bool> _restoreCache() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(_kCacheKey);
      if (raw == null || raw.isEmpty) return false;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      _geoToken = (m['geovisearthToken'] ?? '').toString().trim();
      _tk = (m['tiandituTk'] ?? '').toString().trim();
      final p = (m['prefer'] ?? 'auto').toString().trim().toLowerCase();
      if (p.isNotEmpty) _prefer = p;
      _engine = m['engine'] == 'dart' ? 'dart' : 'gl';
      return true;
    } catch (_) {
      return false; // 缓存坏了就当没有，别影响建图
    }
  }

  static Future<void> _saveCache() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(
        _kCacheKey,
        jsonEncode({
          'geovisearthToken': _geoToken,
          'tiandituTk': _tk,
          'prefer': _prefer,
          'engine': _engine,
        }),
      );
    } catch (_) {
      // 存不进就算了，下次继续走网络
    }
  }
}
