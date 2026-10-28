import '../models/activity.dart';
import '../models/article.dart';
import 'api_client.dart';
import 'api_config.dart';
import '../utils/json_num.dart';

/// 活动 / 文章的统一数据入口
///
/// 两块内容都是「用户投稿 → 后台审核 → 前端可见」的同一套流程，
/// 放一个 service 里省得两套代码各写一遍错误处理。
class ContentService {
  // ------------------------------------------------------------ 活动

  /// 活动列表（只返回审核通过的，后端已按开始时间升序）
  static Future<List<Activity>> fetchActivities({int size = 30}) async {
    if (!ApiConfig.enabled) return const [];
    try {
      final data = await ApiClient.get('/activities', {'size': '$size'});
      if (data is List) {
        return data
            .whereType<Map>()
            .map((e) => Activity.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
      return const [];
    } catch (_) {
      return const [];
    }
  }

  /// 我发布的活动（含待审核 / 被拒绝，用来看审核进度）
  static Future<List<Activity>> fetchMyActivities() async {
    if (!ApiConfig.enabled || ApiClient.token == null) return const [];
    try {
      final data = await ApiClient.get('/activities/mine');
      if (data is List) {
        return data
            .whereType<Map>()
            .map((e) => Activity.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
      return const [];
    } catch (_) {
      return const [];
    }
  }

  /// 活动详情（顺带拿到「我是否已报名」）
  static Future<Activity?> fetchActivity(String id) async {
    if (!ApiConfig.enabled) return null;
    try {
      final data = await ApiClient.get('/activities/$id');
      if (data is Map) return Activity.fromJson(Map<String, dynamic>.from(data));
      return null;
    } catch (_) {
      return null;
    }
  }

  /// 发布活动（进待审核）
  static Future<({bool ok, String msg})> submitActivity({
    required String title,
    required String startAt,
    String endAt = '',
    String location = '',
    String fee = '',
    int maxJoin = 0,
    String contact = '',
    String cover = '',
    String summary = '',
    String content = '',
  }) async {
    if (ApiClient.token == null) {
      return (ok: false, msg: '请先登录后再发布');
    }
    try {
      final data = await ApiClient.post('/activities', {
        'title': title,
        'start_at': startAt,
        'end_at': endAt,
        'location': location,
        'fee': fee,
        'max_join': maxJoin,
        'contact': contact,
        'cover': cover,
        'summary': summary,
        'content': content,
      });
      final m = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
      return (ok: true, msg: (m['message'] ?? '已提交审核').toString());
    } catch (e) {
      return (ok: false, msg: _msgOf(e));
    }
  }

  /// 报名参加
  static Future<({bool ok, String msg, int joinCount})> joinActivity(
      String id) async {
    if (ApiClient.token == null) {
      return (ok: false, msg: '请先登录后再报名', joinCount: 0);
    }
    try {
      final data = await ApiClient.post('/activities/$id/join', const {});
      final m = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
      return (
        ok: true,
        msg: (m['message'] ?? '报名成功').toString(),
        joinCount: jsonInt(m['join_count']) ?? 0,
      );
    } catch (e) {
      return (ok: false, msg: _msgOf(e), joinCount: 0);
    }
  }

  // ------------------------------------------------------------ 文章

  /// 文章列表；category 为空表示全部
  static Future<List<Article>> fetchArticles({
    String category = '',
    int size = 30,
  }) async {
    if (!ApiConfig.enabled) return const [];
    try {
      final data = await ApiClient.get('/articles', {
        'size': '$size',
        if (category.isNotEmpty) 'category': category,
      });
      if (data is List) {
        return data
            .whereType<Map>()
            .map((e) => Article.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
      return const [];
    } catch (_) {
      return const [];
    }
  }

  /// 我投稿的文章（含待审核 / 被拒绝）
  static Future<List<Article>> fetchMyArticles() async {
    if (!ApiConfig.enabled || ApiClient.token == null) return const [];
    try {
      final data = await ApiClient.get('/articles/mine');
      if (data is List) {
        return data
            .whereType<Map>()
            .map((e) => Article.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
      return const [];
    } catch (_) {
      return const [];
    }
  }

  /// 文章详情（带正文，后端会 +1 浏览）
  static Future<Article?> fetchArticle(String id) async {
    if (!ApiConfig.enabled) return null;
    try {
      final data = await ApiClient.get('/articles/$id');
      if (data is Map) return Article.fromJson(Map<String, dynamic>.from(data));
      return null;
    } catch (_) {
      return null;
    }
  }

  /// 投稿文章（进待审核）
  static Future<({bool ok, String msg})> submitArticle({
    required String title,
    required String content,
    String category = 'skill',
    String cover = '',
    String summary = '',
  }) async {
    if (ApiClient.token == null) {
      return (ok: false, msg: '请先登录后再投稿');
    }
    try {
      final data = await ApiClient.post('/articles', {
        'title': title,
        'content': content,
        'category': category,
        'cover': cover,
        'summary': summary,
      });
      final m = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
      return (ok: true, msg: (m['message'] ?? '已提交审核').toString());
    } catch (e) {
      return (ok: false, msg: _msgOf(e));
    }
  }

  /// 从异常里取出后端返回的中文提示
  static String _msgOf(Object e) {
    final s = e.toString();
    for (final p in ['ApiException: ', 'Exception: ']) {
      if (s.startsWith(p)) return s.substring(p.length).trim();
    }
    return '操作失败，请稍后重试';
  }
}
