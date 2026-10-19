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

  /// 后端是否返回「接口不存在」→ 说明关注功能尚未部署
  /// 注意：部分服务器（如带 proxy_intercept_errors 的 nginx）会把 PHP 的 404
  /// 替换成 HTML 错误页，此时 jsonDecode 抛 FormatException，同样按不可用处理
  static bool _isNotAvailable(Object e) {
    final s = e.toString();
    return s.contains('接口不存在') ||
        s.contains('404') ||
        s.contains('FormatException') ||
        s.contains('<html');
  }

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
