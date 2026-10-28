import 'package:flutter/foundation.dart' show visibleForTesting;

import 'api_client.dart';
import 'api_config.dart';
import '../models/user_profile.dart';
/// 关注 / 粉丝：资料、关注切换、粉丝/关注列表
/// 后端未升级（无 /users 路由）时，走演示数据并标记功能不可用
class FollowService {
  static bool get _demo => !ApiConfig.enabled;

  /// 拉取某个用户的公开资料
  static Future<UserProfile> fetchProfile(String userId) async {
    if (_demo) return _demoProfile(userId);
    try {
      final data = await ApiClient.get('/users/$userId') as Map;
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
      final data = await ApiClient.get('/users/me') as Map;
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
          await ApiClient.post('/users/$userId/follow') as Map;
      return (
        following: (data['following'] as bool?) ?? !currentlyFollowing,
        followerCount: (data['followerCount'] as num?)?.toInt() ?? 0,
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
      final data = await ApiClient.get('/users/$userId/followers') as List;
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
      final data = await ApiClient.get('/users/$userId/following') as List;
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
  ///   现在只认两种「真的没有」：
  ///     ① 后端明说「接口不存在」（路由没挂上，块尾兜底那条）
  ///     ② 整段返回是 HTML 错误页，且**没带任何业务文案**（老后端 404 被
  ///        nginx 换成静态页）：这种情况连错误原因都读不到，只能按不可用处理。
  ///   其余一律原样抛出，让用户看到服务器给的真实原因。
  static bool _isNotAvailable(Object e) {
    if (e is ApiException) {
      if (e.message.contains('接口不存在')) return true;
      // 老后端 + nginx：404 被换成 HTML 静态页，读不到任何业务文案
      return e.html && e.message.contains('服务器开小差');
    }
    // 兜底：万一还有别处抛来的裸异常
    final s = e.toString();
    return s.contains('接口不存在') || s.contains('at character 1) <html');
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
