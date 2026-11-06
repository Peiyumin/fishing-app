import '../models/fishing_spot.dart';
import '../models/spot_comment.dart';
import '../models/spot_report.dart';
import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'api_config.dart';
import '../utils/json_num.dart';

/// 钓点服务
/// 对接自建后端 /api/spots；后端不可用或未配置时自动走「演示模式」
///
/// kind：venue=本地钓场（审核后显示） wild=野钓点（地图标记实时显示） shop=渔具店（审核后显示）
class SpotService {
  // ---------- 演示模式本地存储（不持久化，仅预览） ----------
  static final List<FishingSpot> _userSpots = [];
  static final Map<String, int> _reportCounts = {};

  /// 仅测试用：注入一批固定钓点（null = 走真实接口 / 演示数据）
  @visibleForTesting
  static List<FishingSpot>? testSpotsOverride;
  static final List<SpotReport> _demoReports = [
    SpotReport(
      id: 'r1',
      spotId: 's1',
      spotName: '千岛湖中心渔场',
      reason: '坐标错误',
      note: '实际入口在东侧码头，地图点偏了约 1.2 公里。',
      createdAt: DateTime.now().subtract(const Duration(days: 2)),
    ),
    SpotReport(
      id: 'r2',
      spotId: 's3',
      spotName: '青山湖黑坑',
      reason: '已收费',
      note: '现在正钓 200/4h，偷驴 100，建议更新价格。',
      createdAt: DateTime.now().subtract(const Duration(days: 1)),
    ),
  ];

  /// 返回全部钓点（演示模式会把报错数合并进对象）
  static Future<List<FishingSpot>> fetchSpots({String keyword = ''}) async {
    // 仅测试用：注入固定数据，绕开网络与演示数据（v2.1.69 排序回归用）
    final injected = testSpotsOverride;
    if (injected != null) {
      var all = List<FishingSpot>.from(injected);
      if (keyword.isNotEmpty) {
        all = all
            .where((s) =>
                s.name.contains(keyword) ||
                s.address.contains(keyword) ||
                s.description.contains(keyword))
            .toList();
      }
      return all;
    }
    if (!ApiConfig.enabled) {
      await Future.delayed(const Duration(milliseconds: 200));
      var all = [..._userSpots, ...demoSpots];
      if (keyword.isNotEmpty) {
        all = all
            .where((s) =>
                s.name.contains(keyword) ||
                s.address.contains(keyword) ||
                s.description.contains(keyword))
            .toList();
      }
      return all
          .map((s) => s.copyWith(reportCount: _reportCounts[s.id] ?? 0))
          .toList();
    }
    try {
      // 后端 /spots 支持 keyword：按 名称 / 简介 / 地址 模糊匹配
      final data = jsonList(await ApiClient.get('/spots',
          keyword.isEmpty ? null : {'keyword': keyword}));
      return data.map((row) => _fromApi(row as Map)).toList();
    } catch (_) {
      // 后端不可达：列表页回落到演示数据（让用户还能看到界面）；
      // 但**带关键词的搜索**必须返回空 —— 否则用户搜「许昌」会看到
      // 千岛湖、青山湖这些演示钓点，误以为库里就这些数据。
      if (keyword.isNotEmpty) return const <FishingSpot>[];
      return [..._userSpots, ...demoSpots]
          .map((s) => s.copyWith(reportCount: _reportCounts[s.id] ?? 0))
          .toList();
    }
  }

  /// 按 kind 拉取（venue=钓场 / wild=野钓点 / shop=渔具店）
  static Future<List<FishingSpot>> fetchSpotsByKind(String kind) async {
    if (!ApiConfig.enabled) {
      final all = await fetchSpots();
      return all.where((s) => s.kind == kind).toList();
    }
    try {
      final data =
          jsonList(await ApiClient.get('/spots', {'kind': kind}));
      return data.map((row) => _fromApi(row as Map)).toList();
    } catch (_) {
      final all = await fetchSpots();
      return all.where((s) => s.kind == kind).toList();
    }
  }

  /// 后端 JSON 行 → 模型（含 Phase F 新字段）
  /// 仅测试用：把后端原始行解析成模型，供接口契约测试直接调用
  @visibleForTesting
  static FishingSpot mapApiRow(Map r) => _fromApi(r);

  static FishingSpot _fromApi(Map r) {
    return FishingSpot(
      id: (r['id'] ?? '').toString(),
      name: (r['name'] ?? '未命名钓点').toString(),
      type: (r['type'] ?? '野钓').toString(),
      kind: (r['kind'] as String?)?.isNotEmpty == true
          ? r['kind'] as String
          : 'wild',
      status: jsonInt(r['status']) ?? 1,
      lat: jsonDouble(r['lat']) ?? 0,
      lng: jsonDouble(r['lng']) ?? 0,
      rating: jsonDouble(r['rating']) ?? 0,
      description: (r['description'] ?? '').toString(),
      coverUrl: ApiConfig.mediaUrl((r['cover'] as String?)?.isNotEmpty == true
          ? r['cover'] as String
          : null),
      imageUrls: ApiConfig.mediaList(r['images']),
      address: (r['address'] ?? '').toString(),
      fee: (r['fee'] ?? '').toString(),
      fish: (r['fish'] ?? '').toString(),
      tags: (r['tags'] ?? '').toString(),
      phone: (r['phone'] ?? '').toString(),
      delivery: jsonInt(r['delivery']) == 1,
      // 后端没这个字段（老版本）时按「精确」处理：老数据的坐标都是点选/导入来的
      coordPrecise: jsonInt(r['coord_precise']) != 0,
      reportCount: jsonInt(r['report_count']) ?? 0,
      verified: jsonInt(r['verified']) == 1,
      commentCount: jsonInt(r['comment_count']) ?? 0,
    );
  }

  /// 按类型筛选（野钓 / 路亚 / 黑坑 / 海钓）
  static List<FishingSpot> filterByType(List<FishingSpot> all, String? type) {
    if (type == null || type == '全部') return all;
    return all.where((s) => s.type == type).toList();
  }

  /// 某钓点当前报错数（演示模式辅助）
  static int reportCountFor(String spotId) => _reportCounts[spotId] ?? 0;

  /// 发布钓点（野钓点 kind=wild 直接显示；钓场/渔具店走后端审核）
  static Future<void> addSpot({
    required String name,
    required String type,
    required String description,
    required double lat,
    required double lng,
    String kind = 'wild',
    String address = '',
    String fee = '',
    String fish = '',
    String tags = '',
    String cover = '',
    List<String> images = const [], // 环境展示图（服务器绝对 URL，最多 9 张）
    String phone = '',
    double rating = 0,
    bool delivery = false,
    bool coordPrecise = true,
  }) async {
    if (!ApiConfig.enabled) {
      _userSpots.insert(
        0,
        FishingSpot(
          id: 'u${DateTime.now().millisecondsSinceEpoch}',
          name: name,
          type: type,
          kind: kind,
          description: description,
          lat: lat,
          lng: lng,
          rating: rating,
          reportCount: 0,
          verified: false,
          address: address,
          fee: fee,
          fish: fish,
          tags: tags,
          phone: phone,
          delivery: delivery,
        ),
      );
      return;
    }
    if (ApiClient.token == null) throw Exception('请先登录');
    await ApiClient.post('/spots', {
      'name': name,
      'type': type,
      'description': description,
      'lat': lat,
      'lng': lng,
      'kind': kind,
      'address': address,
      'fee': fee,
      'fish': fish,
      'tags': tags,
      if (cover.isNotEmpty) 'cover': cover,
      'images': images,
      'phone': phone,
      'rating': rating,
      'delivery': delivery,
      // v44：告诉后端这个坐标是「实测」还是「地址解析出来的粗坐标」，
      // 决定详情页导航时按坐标走还是按文字地址走
      'coord_precise': coordPrecise ? 1 : 0,
    });
  }

  /// 文字地址 → 坐标（v44）
  ///
  /// 走自家后端 `/geo/forward`：高德 Web 服务 Key 是服务端 Key，绝不能放客户端。
  /// 后端没配 Key 时会用 OSM 兜底，所以这个接口在没有 High德 Key 的情况下也能用。
  ///
  /// 返回 null 表示解析失败（地址太模糊、没网、没登录…），调用方应当提示用户
  /// 「在地图上点一下位置」而不是硬拿一个错坐标去提交。
  ///
  /// ★ 解析出来的坐标只到街道级，调用方必须把它当作 `coordPrecise = false` 用。
  static Future<GeoPoint?> geocodeAddress(String address,
      {String city = ''}) async {
    if (!ApiConfig.enabled) return null;
    final addr = address.trim();
    if (addr.length < 4) return null;
    if (ApiClient.token == null) return null;
    try {
      final data = jsonMap(await ApiClient.post('/geo/forward', {
        'address': addr,
        if (city.isNotEmpty) 'city': city,
      }));
      return GeoPoint(
        lat: jsonDouble(data['lat']) ?? 0,
        lng: jsonDouble(data['lng']) ?? 0,
        levelText: (data['level_text'] ?? '').toString(),
        formatted: (data['formatted'] ?? '').toString(),
        source: (data['source'] ?? '').toString(),
      );
    } catch (_) {
      return null;
    }
  }

  /// 钓点报错
  /// 测试用：记录最近一次 [reportSpot] 实际会发出去的请求体。
  /// 生产环境只是个赋值，没有副作用；测试靠它断言「坐标真的传下去了」。
  @visibleForTesting
  static Map<String, dynamic>? testLastReportBody;

  /// 提交钓点报错
  ///
  /// [lat]/[lng]/[accuracy] 是 v2.1.76 加的：报「坐标错误」时把钓友
  /// 当时站的位置一起传上去。后台能看到「报点坐标距原坐标 380 米」并一键采纳，
  /// 这是纠偏后仍不准的钓点最靠谱的数据源（高德的 POI 常是管理处/大门口，
  /// 只有到过现场的人的 GPS 才知道真正的下竿位置）。
  static Future<void> reportSpot({
    required String spotId,
    required String spotName,
    required String reason,
    String? note,
    double? lat,
    double? lng,
    double? accuracy,
  }) async {
    // 请求体先拼好再记一份（测试断言用）：只有真的拿到位置才带坐标，
    // 没给定位权限的用户照样能报错，只是不带坐标。
    // accuracy 为 0 / 负数时不带 —— 那是「拿不到精度」而不是「精度 0 米」。
    final payload = <String, dynamic>{
      'reason': reason,
      'note': note,
      if (lat != null && lng != null) ...{'lat': lat, 'lng': lng},
      if (accuracy != null && accuracy > 0) 'accuracy': accuracy,
    };
    testLastReportBody = payload;

    if (!ApiConfig.enabled) {
      _demoReports.insert(
        0,
        SpotReport(
          id: 'r${DateTime.now().millisecondsSinceEpoch}',
          spotId: spotId,
          spotName: spotName,
          reason: reason,
          note: note,
          createdAt: DateTime.now(),
        ),
      );
      _reportCounts[spotId] = (_reportCounts[spotId] ?? 0) + 1;
      return;
    }
    if (ApiClient.token == null) throw Exception('请先登录');
    await ApiClient.post('/spots/$spotId/report', payload);
  }

  /// 拉取报错列表（用户端按钓点详情展示报错数即可；演示模式返回内置报错）
  static Future<List<SpotReport>> fetchReports() async {
    await Future.delayed(const Duration(milliseconds: 150));
    return List<SpotReport>.from(_demoReports);
  }

  // ---------------- 钓点评论（v16：需后台审核后展示） ----------------

  /// 某个钓点「已审核通过」的评论列表（公开接口，未登录也能看）
  static Future<List<SpotComment>> fetchComments(String spotId) async {
    if (!ApiConfig.enabled) return const [];
    final data = await ApiClient.get('/spots/$spotId/comments');
    if (data is! List) return const [];
    return data
        .whereType<Map>()
        .map((e) => SpotComment.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// 发表评论：提交后进入待审核，后台通过才在列表里显示
  static Future<void> addComment(String spotId, String content) async {
    if (!ApiConfig.enabled) {
      throw Exception('演示模式暂不支持评论');
    }
    if (ApiClient.token == null) throw Exception('请先登录');
    await ApiClient.post('/spots/$spotId/comment', {'content': content});
  }
}

/// 地址解析结果（坐标 + 精度说明）
///
/// 由 [SpotService.geocodeAddress] 返回。注意它**永远不是精确坐标**：
/// 文字地址能解析到门牌号级已经很好了，绝大多数只到街道/村口。
/// 所以拿到它之后必须按 `coordPrecise = false` 提交，导航时才会改用文字地址。
class GeoPoint {
  final double lat;
  final double lng;

  /// 精度人话：门牌号级 / 道路级 / 区县级 / 未知精度
  final String levelText;

  /// 服务端规范化后的地址（可以直接回填到地址框）
  final String formatted;

  /// amap = 高德，osm = OpenStreetMap 兜底
  final String source;

  const GeoPoint({
    required this.lat,
    required this.lng,
    this.levelText = '',
    this.formatted = '',
    this.source = '',
  });

  bool get valid => lat.abs() > 0.0001 && lng.abs() > 0.0001;

  /// 「街道级 · 高德」这种短说明，给用户看
  String get hint {
    final lv = levelText.isEmpty ? '地址级' : levelText;
    return source == 'amap' ? lv : '$lv · OpenStreetMap';
  }
}
