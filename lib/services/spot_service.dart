import '../models/fishing_spot.dart';
import '../models/spot_comment.dart';
import '../models/spot_report.dart';
import 'api_client.dart';
import 'api_config.dart';

/// 钓点服务
/// 对接自建后端 /api/spots；后端不可用或未配置时自动走「演示模式」
///
/// kind：venue=本地钓场（审核后显示） wild=野钓点（地图标记实时显示） shop=渔具店（审核后显示）
class SpotService {
  // ---------- 演示模式本地存储（不持久化，仅预览） ----------
  static final List<FishingSpot> _userSpots = [];
  static final Map<String, int> _reportCounts = {};
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
      final data = await ApiClient.get('/spots',
          keyword.isEmpty ? null : {'keyword': keyword}) as List;
      return data.map((row) => _fromApi(row as Map)).toList();
    } catch (_) {
      // 后端不可达：回落演示数据
      var all = [..._userSpots, ...demoSpots];
      if (keyword.isNotEmpty) {
        all = all.where((s) => s.name.contains(keyword)).toList();
      }
      return all
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
          await ApiClient.get('/spots', {'kind': kind}) as List;
      return data.map((row) => _fromApi(row as Map)).toList();
    } catch (_) {
      final all = await fetchSpots();
      return all.where((s) => s.kind == kind).toList();
    }
  }

  /// 后端 JSON 行 → 模型（含 Phase F 新字段）
  static FishingSpot _fromApi(Map r) {
    return FishingSpot(
      id: r['id'] as String,
      name: (r['name'] ?? '未命名钓点') as String,
      type: (r['type'] ?? '野钓') as String,
      kind: (r['kind'] as String?)?.isNotEmpty == true
          ? r['kind'] as String
          : 'wild',
      status: (r['status'] as num?)?.toInt() ?? 1,
      lat: (r['lat'] as num?)?.toDouble() ?? 0,
      lng: (r['lng'] as num?)?.toDouble() ?? 0,
      rating: (r['rating'] as num?)?.toDouble() ?? 0,
      description: (r['description'] ?? '') as String,
      coverUrl: ApiConfig.mediaUrl((r['cover'] as String?)?.isNotEmpty == true
          ? r['cover'] as String
          : null),
      imageUrls: ApiConfig.mediaList(r['images']),
      address: (r['address'] ?? '') as String,
      fee: (r['fee'] ?? '') as String,
      fish: (r['fish'] ?? '') as String,
      tags: (r['tags'] ?? '') as String,
      phone: (r['phone'] ?? '') as String,
      reportCount: (r['report_count'] as num?)?.toInt() ?? 0,
      verified: (r['verified'] as num?)?.toInt() == 1,
      commentCount: (r['comment_count'] as num?)?.toInt() ?? 0,
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
    });
  }

  /// 钓点报错
  static Future<void> reportSpot({
    required String spotId,
    required String spotName,
    required String reason,
    String? note,
  }) async {
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
    await ApiClient.post('/spots/$spotId/report', {'reason': reason, 'note': note});
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
