import 'package:flutter/foundation.dart' show visibleForTesting;

import 'api_client.dart';
import 'api_config.dart';
import '../models/user_profile.dart';
import '../utils/json_num.dart';
/// 关注 / 粉丝：资料、关注切换、粉丝/关注列表
/// 后端未升级（无 /users 路由）时，走演示数据并标记功能不可用
class FollowService {
  static bool get _demo => !ApiConfig.enabled;

  /// 拉取某个用户的公开资料
  static Future<UserProfile> fetchProfile(String userId) async {
    if (_demo) return _demoProfile(userId);
    try {
      final data = jsonMap(await ApiClient.get('/users/$userId'));
      return UserProfile.fromJson(Map<String, dynamic>.from(data));
    } catch (e) {
      if (_isNotAvailable(e)) throw const FollowNotAvailableException();
      rethrow;
    }
  }

  /// 我的资料（含计数）
  static Future<UserProfile> fetchMe() async {
    if (_demo) return _demoProfile('me', isMe: true);
    try {
      final data = jsonMap(await ApiClient.get('/users/me'));
      return UserProfile.fromJson(Map<String, dynamic>.from(data));
    } catch (e) {
      if (_isNotAvailable(e)) throw const FollowNotAvailableException();
      rethrow;
    }
  }

  /// 关注 / 取消关注，返回 (是否已关注, 粉丝数)
  static Future<({bool following, int followerCount})> toggleFollow(
      String userId, bool currentlyFollowing) async {
    if (_demo) {
      // 演示模式：本地切换
      return (following: !currentlyFollowing, followerCount: 0);
    }
    try {
      final data =
          jsonMap(await ApiClient.post('/users/$userId/follow'));
      return (
        following: jsonBool(data['following'], fallback: !currentlyFollowing),
        followerCount: jsonInt(data['followerCount']) ?? 0,
      );
    } catch (e) {
      if (_isNotAvailable(e)) throw const FollowNotAvailableException();
      rethrow;
    }
  }

  /// 粉丝列表（关注了 userId 的人）
  static Future<List<UserProfile>> fetchFollowers(String userId) async {
    if (_demo) return [];
    try {
      final data = jsonList(await ApiClient.get('/users/$userId/followers'));
      return data
          .map((e) => UserProfile.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e) {
      if (_isNotAvailable(e)) throw const FollowNotAvailableException();
      rethrow;
    }
  }

  /// 关注列表（userId 关注的人）
  static Future<List<UserProfile>> fetchFollowing(String userId) async {
    if (_demo) return [];
    try {
      final data = jsonList(await ApiClient.get('/users/$userId/following'));
      return data
          .map((e) => UserProfile.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e) {
      if (_isNotAvailable(e)) throw const FollowNotAvailableException();
      rethrow;
    }
  }

  /// 后端是否**真的**没有关注模块
  ///
  /// ★ v2.1.49 修了一个误判：以前只要异常串里带 `404` 就算「未升级」，
  ///   于是一旦目标用户不存在（后端 `api_fail(404,'用户不存在')`），
  ///   用户看到的就是「关注/粉丝功能需升级后端后启用」——
  ///   而关注功能其实早就上线了，这句提示纯属冤枉。
  ///
  ///   现在只认一种「真的没有」：后端**明说**「接口不存在」（users 块尾那条
  ///   兜底路由没挂上才会说的话）。
  ///
  ///   至于「整段返回 HTML 错误页」——那只能说明「出错了」，不能说「没升级」
  ///   （老后端把 404 换成 nginx 静态页时，用户不存在也是这个表现）。
  ///   这种情况原样抛出，界面显示 [ApiException] 给的「服务器开小差了，请稍后再试」。
  static bool _isNotAvailable(Object e) {
    if (e is ApiException) return e.message.contains('接口不存在');
    return e.toString().contains('接口不存在');
  }

  /// 仅测试用：把私有判据暴露出来，锁住「用户不存在 ≠ 后端未升级」这条
  @visibleForTesting
  static bool debugIsNotAvailable(Object e) => _isNotAvailable(e);

  static UserProfile _demoProfile(String id, {bool isMe = false}) {
    return UserProfile(
      id: id,
      nickname: isMe ? '我（演示）' : '演示钓友',
      followerCount: 0,
      followingCount: 0,
      postCount: 0,
      isMe: isMe,
    );
  }
}
