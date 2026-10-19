import 'package:flutter/material.dart';

import '../models/user_profile.dart';
import 'api_client.dart';
import 'api_config.dart';

/// 全局登录态管理（Provider）
/// 对接自建后端 /api/auth（手机号 + 密码），token 保存在内存中
class SessionProvider extends ChangeNotifier {
  String? _token;
  String? _userId;
  String? _nickname;
  String? _avatar;

  bool get isLoggedIn => _token != null;
  String? get userId => _userId;
  String? get nickname => _nickname;
  String? get avatar => _avatar;

  /// 头像的完整可访问地址（相对路径自动拼站点根，绝对地址自动修端口）
  String? get avatarUrl => ApiConfig.mediaUrl(_avatar);

  /// 登录（手机号 + 密码）
  Future<void> signIn(String phone, String password) async {
    final data = await ApiClient.post(
      '/auth/login',
      {'phone': phone, 'password': password},
    ) as Map;
    _apply(data);
  }

  /// 注册（手机号 + 密码 + 昵称），成功后自动登录
  Future<void> signUp(String phone, String password, String nickname) async {
    final data = await ApiClient.post('/auth/register', {
      'phone': phone,
      'nickname': nickname,
      'password': password,
    }) as Map;
    _apply(data);
  }

  void _apply(Map data) {
    _token = data['token'] as String?;
    _userId = data['id'] as String?;
    _nickname = (data['nickname'] as String?) ?? '钓友';
    _avatar = data['avatar'] as String?;
    ApiClient.setToken(_token);
    notifyListeners();
  }

  /// 修改我的资料（昵称 / 头像），成功后同步全局状态
  Future<UserProfile> updateProfile({String? nickname, String? avatar}) async {
    final data = await ApiClient.post('/users/me/profile', {
      if (nickname != null) 'nickname': nickname,
      if (avatar != null) 'avatar': avatar,
    }) as Map;
    final profile = UserProfile.fromJson(Map<String, dynamic>.from(data));
    _nickname = profile.nickname;
    _avatar = profile.avatar;
    notifyListeners();
    return profile;
  }

  /// 修改登录密码（oldPassword / newPassword）
  Future<void> changePassword(String oldPassword, String newPassword) async {
    if (!ApiConfig.enabled) throw Exception('未配置后端，演示模式不支持改密码');
    await ApiClient.post('/users/me/password', {
      'oldPassword': oldPassword,
      'newPassword': newPassword,
    });
  }

  Future<void> signOut() async {
    _token = null;
    _userId = null;
    _nickname = null;
    _avatar = null;
    ApiClient.setToken(null);
    notifyListeners();
  }
}
