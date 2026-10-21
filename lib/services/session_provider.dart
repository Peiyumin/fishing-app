import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/member.dart';
import '../models/user_profile.dart';
import 'api_client.dart';
import 'api_config.dart';

/// 全局登录态管理（Provider）
/// 对接自建后端 /api/auth（手机号 + 密码）
///
/// 登录态持久化（需求：退出 App 不掉线，只有主动退出才登出，重装才需重新登录）：
/// token / userId / nickname / avatar 全部落本地 SharedPreferences，
/// 启动时 [restore] 恢复；[signOut] 才清除。
class SessionProvider extends ChangeNotifier {
  static const _kToken = 'session_token';
  static const _kUserId = 'session_user_id';
  static const _kNickname = 'session_nickname';
  static const _kAvatar = 'session_avatar';
  static const _kVipLevel = 'session_vip_level';
  static const _kVipName = 'session_vip_name';
  static const _kVipColor = 'session_vip_color';
  static const _kVipColor2 = 'session_vip_color2';
  static const _kVipExpire = 'session_vip_expire';

  String? _token;
  String? _userId;
  String? _nickname;
  String? _avatar;
  int _vipLevel = 0;
  String _vipName = '';
  Color _vipColor = MemberStyle.normalColor;
  Color _vipColor2 = MemberStyle.normalColor2;
  String _vipExpire = '';

  bool get isLoggedIn => _token != null;
  String? get userId => _userId;
  String? get nickname => _nickname;
  String? get avatar => _avatar;

  /// 当前登录用户的会员样式（用于头像会员框等）
  MemberStyle get vip => MemberStyle(
        level: _vipLevel,
        name: _vipName,
        color: _vipColor,
        color2: _vipColor2,
        expire: _vipExpire,
      );

  /// 头像的完整可访问地址（相对路径自动拼站点根，绝对地址自动修端口）
  String? get avatarUrl => ApiConfig.mediaUrl(_avatar);

  /// 启动时从本地恢复登录态（在 runApp 前调用）
  Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString(_kToken);
    _userId = prefs.getString(_kUserId);
    _nickname = prefs.getString(_kNickname);
    _avatar = prefs.getString(_kAvatar);
    _vipLevel = prefs.getInt(_kVipLevel) ?? 0;
    _vipName = prefs.getString(_kVipName) ?? '';
    _vipColor = Color(prefs.getInt(_kVipColor) ?? MemberStyle.normalColor.value);
    _vipColor2 = Color(prefs.getInt(_kVipColor2) ?? MemberStyle.normalColor2.value);
    _vipExpire = prefs.getString(_kVipExpire) ?? '';
    ApiClient.setToken(_token);
    notifyListeners();
  }

  /// 登录（手机号 + 密码）
  Future<void> signIn(String phone, String password) async {
    final data = await ApiClient.post(
      '/auth/login',
      {'phone': phone, 'password': password},
    ) as Map;
    await _apply(data);
  }

  /// 注册（手机号 + 密码 + 昵称），成功后自动登录
  Future<void> signUp(String phone, String password, String nickname) async {
    final data = await ApiClient.post('/auth/register', {
      'phone': phone,
      'nickname': nickname,
      'password': password,
    }) as Map;
    await _apply(data);
  }

  /// 写入登录态：内存 + 本地持久化
  Future<void> _apply(Map data) async {
    _token = data['token'] as String?;
    _userId = data['id'] as String?;
    _nickname = (data['nickname'] as String?) ?? '钓友';
    _avatar = data['avatar'] as String?;
    _vipLevel = (data['vipLevel'] as num?)?.toInt() ?? 0;
    _vipName = (data['vipName'] as String?) ?? '';
    _vipColor = MemberStyle.parseColor(data['vipColor'], MemberStyle.normalColor);
    _vipColor2 = MemberStyle.parseColor(data['vipColor2'], MemberStyle.normalColor2);
    _vipExpire = (data['vipExpire'] as String?) ?? '';
    ApiClient.setToken(_token);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kToken, _token ?? '');
    await prefs.setString(_kUserId, _userId ?? '');
    await prefs.setString(_kNickname, _nickname ?? '');
    await prefs.setString(_kAvatar, _avatar ?? '');
    await prefs.setInt(_kVipLevel, _vipLevel);
    await prefs.setString(_kVipName, _vipName);
    await prefs.setInt(_kVipColor, _vipColor.value);
    await prefs.setInt(_kVipColor2, _vipColor2.value);
    await prefs.setString(_kVipExpire, _vipExpire);
  }

  /// 修改我的资料（昵称 / 头像），成功后同步全局状态与本地缓存
  Future<UserProfile> updateProfile({String? nickname, String? avatar}) async {
    final data = await ApiClient.post('/users/me/profile', {
      if (nickname != null) 'nickname': nickname,
      if (avatar != null) 'avatar': avatar,
    }) as Map;
    final profile = UserProfile.fromJson(Map<String, dynamic>.from(data));
    _nickname = profile.nickname;
    _avatar = profile.avatar;
    _vipLevel = profile.vip.level;
    _vipName = profile.vip.name;
    _vipColor = profile.vip.color;
    _vipColor2 = profile.vip.color2;
    _vipExpire = profile.vip.expire;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kNickname, _nickname ?? '');
    await prefs.setString(_kAvatar, _avatar ?? '');
    await prefs.setInt(_kVipLevel, _vipLevel);
    await prefs.setString(_kVipName, _vipName);
    await prefs.setInt(_kVipColor, _vipColor.value);
    await prefs.setInt(_kVipColor2, _vipColor2.value);
    await prefs.setString(_kVipExpire, _vipExpire);
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

  /// 退出登录：清内存 + 清本地（用户主动点击才走到这里）
  Future<void> signOut() async {
    _token = null;
    _userId = null;
    _nickname = null;
    _avatar = null;
    _vipLevel = 0;
    _vipName = '';
    _vipColor = MemberStyle.normalColor;
    _vipColor2 = MemberStyle.normalColor2;
    _vipExpire = '';
    ApiClient.setToken(null);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kToken);
    await prefs.remove(_kUserId);
    await prefs.remove(_kNickname);
    await prefs.remove(_kAvatar);
    await prefs.remove(_kVipLevel);
    await prefs.remove(_kVipName);
    await prefs.remove(_kVipColor);
    await prefs.remove(_kVipColor2);
    await prefs.remove(_kVipExpire);
  }
}
