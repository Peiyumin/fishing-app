import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/member.dart';
import '../models/user_profile.dart';
import '../utils/county_label.dart';
import 'account_history.dart';
import 'api_client.dart';
import 'api_config.dart';
import 'fish_service.dart';
import 'geo_place.dart';
import 'location_service.dart';
import '../utils/json_num.dart';

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
  static const _kCover = 'session_cover';
  static const _kBio = 'session_bio';
  static const _kVipLevel = 'session_vip_level';
  static const _kVipName = 'session_vip_name';
  static const _kVipColor = 'session_vip_color';
  static const _kVipColor2 = 'session_vip_color2';
  static const _kVipExpire = 'session_vip_expire';

  String? _token;
  String? _userId;
  String? _nickname;
  String? _avatar;
  String? _cover;
  String? _bio;
  int _vipLevel = 0;
  String _vipName = '';
  Color _vipColor = MemberStyle.normalColor;
  Color _vipColor2 = MemberStyle.normalColor2;
  String _vipExpire = '';

  bool get isLoggedIn => _token != null;
  String? get userId => _userId;

  /// 当前登录用户是否为有效会员（等级 > 0 且未过期）
  bool get isMember {
    if (_vipLevel <= 0) return false;
    if (_vipExpire.isEmpty) return true;
    try {
      // 以前这里直接 DateTime.parse，后台把日期格式改一下（或存了空串）
    // 整个「我的」页就会崩。解析不出来按「未过期」处理更保守？不 ——
    // 宁可当未开通，也不要让会员权益凭空消失以外的崩溃发生。
    final d = jsonDate(_vipExpire);
    return d != null && d.isAfter(DateTime.now());
    } catch (_) {
      return true;
    }
  }
  String? get nickname => _nickname;
  String? get avatar => _avatar;

  /// 个人主页背景图（原始相对路径）
  String? get cover => _cover;
  String? get bio => _bio;

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

  /// 背景图完整地址（没设置过返回 null，调用方走默认渐变）
  String? get coverUrl {
    final c = _cover;
    if (c == null || c.trim().isEmpty) return null;
    final u = ApiConfig.mediaUrl(c);
    return (u == null || u.isEmpty) ? null : u;
  }

  /// 启动时从本地恢复登录态（在 runApp 前调用）
  Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString(_kToken);
    _userId = prefs.getString(_kUserId);
    _nickname = prefs.getString(_kNickname);
    _avatar = prefs.getString(_kAvatar);
    _cover = prefs.getString(_kCover);
    _bio = prefs.getString(_kBio);
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
    final data = jsonMap(await ApiClient.post(
      '/auth/login',
      {'phone': phone, 'password': password},
    ));
    await _apply(data);
    unawaited(_syncRegPlace());
  }

  /// 注册（手机号 + 密码 + 昵称），成功后自动登录
  Future<void> signUp(String phone, String password, String nickname) async {
    final data = jsonMap(await ApiClient.post('/auth/register', {
      'phone': phone,
      'nickname': nickname,
      'password': password,
    }));
    await _apply(data);
    unawaited(_syncRegPlace());
  }

  /// 补录「注册地」（v2.1.57）
  ///
  /// 个人主页要显示「河南省·禹州市」这一级定位。注册接口本来就能带 place，
  /// 但**短信验证码登录会自动注册**、老账号更是升级前就注册好了 —— 这两类
  /// 都没有值。所以登录成功后补一次：
  ///   · 没给定位权限就直接跳过（不弹授权框，不打扰）；
  ///   · 服务端只在 reg_place 为空时写入，换城市不会把「注册地」改成新城市；
  ///   · 全程失败静默（这是装饰性信息，不能因为它让登录报错）。
  Future<void> _syncRegPlace() async {
    try {
      if (!await LocationService.hasPermission()) return;
      final p = await GeoPlace.current();
      if (p == null || p.isEmpty) return;
      final place = countyLabel(
        city: p.city,
        district: p.district,
        province: p.province,
        withProvince: true,
      );
      if (place.isEmpty) return;
      await ApiClient.post('/users/me/reg-place', {'place': place});
    } catch (_) {
      // 忽略：后端没升级 / 断网 / 定位超时都不影响登录
    }
  }

  /// 发短信验证码（返回体里可能带 debugCode，调试模式下直接给到前端）
  Future<Map> sendSmsCode(String phone) async {
    final data = await ApiClient.post('/auth/sms/send', {'phone': phone});
    return Map<String, dynamic>.from(data as Map);
  }

  /// 手机号 + 短信验证码登录（**没注册过就自动注册**，注册即登录）
  /// 返回 true 表示这次是新注册出来的账号
  Future<bool> signInBySms(String phone, String code, {String? nickname}) async {
    final data = jsonMap(await ApiClient.post('/auth/sms/login', {
      'phone': phone,
      'code': code,
      if (nickname != null && nickname.trim().isNotEmpty)
        'nickname': nickname.trim(),
    }));
    final isNew = data['isNew'] == true;
    await _apply(data);
    unawaited(_syncRegPlace());
    return isNew;
  }

  /// 微信登录（code 由微信 SDK 授权后拿到）
  Future<bool> signInByWechat(String code) async {
    final data = jsonMap(await ApiClient.post('/auth/wechat/login', {'code': code}));
    final isNew = data['isNew'] == true;
    await _apply(data);
    unawaited(_syncRegPlace());
    return isNew;
  }

  /// 本机号码一键登录
  ///
  /// [token] 由运营商取号 SDK 拿到的一次性凭证，**服务端拿它去服务商换真实号码**。
  /// 客户端不上报手机号 —— 否则任何人填别人号码就能登进别人账号。
  Future<bool> signInByOneKey(String token) async {
    final data =
        jsonMap(await ApiClient.post('/auth/onekey/login', {'token': token}));
    final isNew = data['isNew'] == true;
    await _apply(data);
    unawaited(_syncRegPlace());
    return isNew;
  }

  /// 写入登录态：内存 + 本地持久化
  Future<void> _apply(Map data) async {
    _token = data['token'] as String?;
    _userId = data['id'] as String?;
    _nickname = (data['nickname'] as String?) ?? '钓友';
    _avatar = data['avatar'] as String?;
    if (data['cover'] != null) _cover = data['cover'] as String?;
    if (data['bio'] != null) _bio = data['bio'] as String?;
    _vipLevel = jsonInt(data['vipLevel']) ?? 0;
    _vipName = (data['vipName'] as String?) ?? '';
    _vipColor = MemberStyle.parseColor(data['vipColor'], MemberStyle.normalColor);
    _vipColor2 = MemberStyle.parseColor(data['vipColor2'], MemberStyle.normalColor2);
    _vipExpire = (data['vipExpire'] as String?) ?? '';
    ApiClient.setToken(_token);
    // 换了账号：图鉴是按账号统计的，旧缓存必须丢，否则显示上一个人的进度
    FishService.clearCache();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kToken, _token ?? '');
    await prefs.setString(_kUserId, _userId ?? '');
    await prefs.setString(_kNickname, _nickname ?? '');
    await prefs.setString(_kAvatar, _avatar ?? '');
    await prefs.setString(_kCover, _cover ?? '');
    await prefs.setString(_kBio, _bio ?? '');
    await prefs.setInt(_kVipLevel, _vipLevel);
    await prefs.setString(_kVipName, _vipName);
    await prefs.setInt(_kVipColor, _vipColor.value);
    await prefs.setInt(_kVipColor2, _vipColor2.value);
    await prefs.setString(_kVipExpire, _vipExpire);
    // 记进「本机历史账号」（设置页可一键切换），登录/注册都会走到这里
    await AccountHistoryStore.remember(Map<String, dynamic>.from(data));
  }

  /// 用历史账号的登录数据直接切回该账号（免密）
  /// 调用方需先确认 token 还有效，失效时不要调用
  Future<void> switchAccount(Map<String, dynamic> data) => _apply(data);

  /// 修改我的资料（昵称 / 头像 / 个性签名），成功后同步全局状态与本地缓存
  Future<UserProfile> updateProfile(
      {String? nickname, String? avatar, String? cover, String? bio}) async {
    final data = jsonMap(await ApiClient.post('/users/me/profile', {
      if (nickname != null) 'nickname': nickname,
      if (avatar != null) 'avatar': avatar,
      if (cover != null) 'cover': cover,
      if (bio != null) 'bio': bio,
    }));
    final profile = UserProfile.fromJson(Map<String, dynamic>.from(data));
    _nickname = profile.nickname;
    _avatar = profile.avatar;
    _cover = profile.cover;
    _bio = profile.bio;
    _vipLevel = profile.vip.level;
    _vipName = profile.vip.name;
    _vipColor = profile.vip.color;
    _vipColor2 = profile.vip.color2;
    _vipExpire = profile.vip.expire;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kNickname, _nickname ?? '');
    await prefs.setString(_kAvatar, _avatar ?? '');
    await prefs.setString(_kCover, _cover ?? '');
    await prefs.setString(_kBio, _bio ?? '');
    await prefs.setInt(_kVipLevel, _vipLevel);
    await prefs.setString(_kVipName, _vipName);
    await prefs.setInt(_kVipColor, _vipColor.value);
    await prefs.setInt(_kVipColor2, _vipColor2.value);
    await prefs.setString(_kVipExpire, _vipExpire);
    return profile;
  }

  /// 会员开通 / 续费后把会员身份写回全局会话（v2.1.61）
  ///
  /// ★ 会员中心下单成功只刷新它自己的 `_info`，不会回写这里。天气 7 天、
  ///   附近钓友这类「进页面时按会员身份放行」的功能，如果不同步，
  ///   用户付完钱回来仍是未开通状态，必须杀掉 App 重开 —— 那是明显的 bug。
  ///   只动会员相关字段，昵称 / 头像 / 登录态一概不碰。
  Future<void> markMember({
    required int level,
    String name = '',
    String expire = '',
  }) async {
    final style = MemberStyle.fromLevel(level);
    _vipLevel = level <= 0 ? 0 : level;
    _vipName = name.isNotEmpty ? name : (level <= 0 ? '' : style.name);
    _vipColor = style.color;
    _vipColor2 = style.color2;
    _vipExpire = expire;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kVipLevel, _vipLevel);
      await prefs.setString(_kVipName, _vipName);
      await prefs.setInt(_kVipColor, _vipColor.value);
      await prefs.setInt(_kVipColor2, _vipColor2.value);
      await prefs.setString(_kVipExpire, _vipExpire);
    } catch (_) {
      // 本地缓存写失败不影响本次会话内的权益
    }
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
    _cover = null;
    _bio = null;
    _vipLevel = 0;
    _vipName = '';
    _vipColor = MemberStyle.normalColor;
    _vipColor2 = MemberStyle.normalColor2;
    _vipExpire = '';
    ApiClient.setToken(null);
    FishService.clearCache();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kToken);
    await prefs.remove(_kUserId);
    await prefs.remove(_kNickname);
    await prefs.remove(_kAvatar);
    await prefs.remove(_kCover);
    await prefs.remove(_kBio);
    await prefs.remove(_kVipLevel);
    await prefs.remove(_kVipName);
    await prefs.remove(_kVipColor);
    await prefs.remove(_kVipColor2);
    await prefs.remove(_kVipExpire);
  }
}
