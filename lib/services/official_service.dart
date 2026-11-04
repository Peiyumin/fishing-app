import 'package:flutter/foundation.dart';

import '../models/official.dart';
import '../utils/json_num.dart';
import 'api_client.dart';

/// 官方工作台服务（v40）
///
/// 三个页面共用的都是这组接口。所有方法都直接抛 [ApiException]：
/// 后端没升级时是 404「接口不存在」，界面上会翻成「后台还没升级到 v40」，
/// 而不是一句看不懂的报错。
class OfficialService {
  // ---------- 仅测试用：注入固定数据，绕开网络（截图 / 回归） ----------
  @visibleForTesting
  static OfficialOverview? testOverview;
  @visibleForTesting
  static List<OfficialNotice>? testNotices;
  @visibleForTesting
  static List<OfficialPost>? testPosts;
  @visibleForTesting
  static List<OfficialUser>? testUsers;
  @visibleForTesting
  static List<OfficialLog>? testLogs;

  /// 工作台概览（三个数字 + 昵称）
  static Future<OfficialOverview> overview() async {
    final injected = testOverview;
    if (injected != null) return injected;
    final data = jsonMap(await ApiClient.get('/official/overview'));
    return OfficialOverview.fromJson(data);
  }

  /// 公告列表（所有官方发的都能看到）
  static Future<List<OfficialNotice>> notices() async {
    final injected = testNotices;
    if (injected != null) return injected;
    final raw = await ApiClient.get('/official/notices');
    return jsonList(raw).map((e) => OfficialNotice.fromJson(jsonMap(e))).toList();
  }

  /// 发公告（[id] 为空 = 新建；有值 = 改自己发过的那条）
  ///
  /// [images] 传**最终可用的地址**（远程 URL）：编辑器在提交前已经把本机
  /// 选中的图片上传成 URL 了，这里不再碰文件 —— 发布页/公告页两条链路的上传
  /// 逻辑各管各的，服务层只负责发 JSON。
  static Future<String> saveNotice({
    String id = '',
    required String title,
    required String content,
    List<String> images = const [],
    bool pinned = true,
  }) async {
    final data = jsonMap(await ApiClient.post('/official/notice', {
      'id': id,
      'title': title,
      'content': content,
      'images': images,
      'pinned': pinned,
    }));
    return (data['id'] ?? '').toString();
  }

  /// 公告详情（普通用户视角，从「消息 → 系统通知」点进来）
  ///
  /// 走的是 /messages/official-notice 而不是 /official/notice：
  /// 后者是工作台接口，只有官方能调，普通用户点公告会被 403。
  static Future<OfficialNotice> noticeDetail(String id) async {
    final data = jsonMap(await ApiClient.get('/messages/official-notice', {'id': id}));
    return OfficialNotice.fromJson(data);
  }

  /// 撤回自己的公告
  static Future<void> deleteNotice(String id) =>
      ApiClient.post('/official/notice/delete', {'id': id});

  /// 公告置顶开关
  static Future<void> pinNotice(String id, {required bool pinned}) =>
      ApiClient.post('/official/notice/pin', {'id': id, 'pinned': pinned});

  /// 帖子列表（[show] = normal / deleted / all）
  static Future<List<OfficialPost>> posts({
    String keyword = '',
    String show = 'normal',
    int page = 1,
  }) async {
    final injected = testPosts;
    if (injected != null) return injected;
    final raw = await ApiClient.get('/official/posts', {
      'kw': keyword,
      'show': show,
      'page': '$page',
    });
    return jsonList(raw).map((e) => OfficialPost.fromJson(jsonMap(e))).toList();
  }

  /// 帖子操作：delete / restore / pin / unpin
  static Future<void> postAction(String id, String action) =>
      ApiClient.post('/official/post', {'id': id, 'action': action});

  /// 用户检索（昵称 / 手机号 / 用户 ID）
  static Future<List<OfficialUser>> users(String keyword) async {
    final injected = testUsers;
    if (injected != null) return injected;
    final raw = await ApiClient.get('/official/users', {'kw': keyword});
    return jsonList(raw).map((e) => OfficialUser.fromJson(jsonMap(e))).toList();
  }

  /// 封禁（[days] = 1 / 7 / 30，0 = 永久）
  static Future<void> ban(String id, {required int days, required String reason}) =>
      ApiClient.post('/official/user/ban', {'id': id, 'days': days, 'reason': reason});

  /// 解封
  static Future<void> unban(String id) =>
      ApiClient.post('/official/user/unban', {'id': id});

  /// 操作记录（最近 50 条）
  static Future<List<OfficialLog>> logs() async {
    final injected = testLogs;
    if (injected != null) return injected;
    final raw = await ApiClient.get('/official/logs');
    return jsonList(raw).map((e) => OfficialLog.fromJson(jsonMap(e))).toList();
  }

  // ══════════════ 钓点管理（v41）══════════════

  @visibleForTesting
  static List<OfficialSpot>? testSpots;
  @visibleForTesting
  static OfficialSpotDraft? testSpotDraft;

  /// 钓点列表：[show] = normal（已上架）/ pending（待审核）/ hidden（已下架）
  static Future<List<OfficialSpot>> spots({
    String keyword = '',
    String kind = '',
    String show = 'normal',
    int page = 1,
  }) async {
    final injected = testSpots;
    if (injected != null) return injected;
    final raw = await ApiClient.get('/official/spots', {
      'kw': keyword,
      'kind': kind,
      'show': show,
      'page': '$page',
    });
    return jsonList(raw).map((e) => OfficialSpot.fromJson(jsonMap(e))).toList();
  }

  /// 单个钓点全字段（含未上架的 —— 待审核的也得能改）
  static Future<OfficialSpotDraft> spot(String id) async {
    final injected = testSpotDraft;
    if (injected != null) return injected;
    final data = await ApiClient.get('/official/spot', {'id': id});
    return OfficialSpotDraft.fromJson(jsonMap(data));
  }

  /// 保存钓点（全字段覆盖）
  static Future<void> saveSpot(OfficialSpotDraft draft) async {
    await ApiClient.post('/official/spot', draft.toJson());
  }
}
