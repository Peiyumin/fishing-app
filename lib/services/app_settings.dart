import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'api_config.dart';
import 'settings_service.dart';

/// 全局偏好（设置页改、其它页面读）
///
/// 三条数据都是「先本地、后同步」：
///   1. 用户点了开关 → 立刻写 SharedPreferences 并 notifyListeners（离线也生效）
///   2. 同时悄悄 POST /settings 上报（失败不影响本地，下次登录再对齐）
///   3. 登录后 [syncFromServer] 拉一次：个性化 / 鱼获隐私以服务端为准，
///      字体大小以本机为准（同一个账号在不同手机上应该各用各的字号）
class AppSettings extends ChangeNotifier {
  AppSettings._();
  static final AppSettings instance = AppSettings._();

  static const _kFont = 'app_font_scale';
  static const _kPersonalized = 'app_personalized';
  static const _kCatchPrivacy = 'app_catch_privacy';
  static const _kConsent = 'app_consent_at';

  /// 字体档位常量（与后端 settings_font_scales() 一一对应）
  static const String fontStandard = 'standard';
  static const String fontLarge = 'large';
  static const String fontXLarge = 'xlarge';

  String _fontLevel = fontStandard;
  bool _personalized = true;
  bool _catchPrivacy = true;
  String _consentAt = '';

  String get fontLevel => _fontLevel;
  bool get personalized => _personalized;

  /// 发布渔获时「钓点是否公开」的默认值
  bool get catchPrivacy => _catchPrivacy;

  /// 同意隐私政策的时间（空串 = 未同意 / 已撤回）
  String get consentAt => _consentAt;

  /// 全局文字缩放倍率。1.0 = 系统默认，不改变任何现有版式。
  double get fontScale {
    switch (_fontLevel) {
      case fontLarge:
        return 1.15;
      case fontXLarge:
        return 1.30;
      default:
        return 1.0;
    }
  }

  String get fontLevelLabel {
    switch (_fontLevel) {
      case fontLarge:
        return '大';
      case fontXLarge:
        return '特大';
      default:
        return '标准';
    }
  }

  /// 启动时读本地
  ///
  /// v2.1.44 起这一步在 runApp **之后**（启动页背后）才跑，所以读完必须
  /// notifyListeners：MyApp 用 AnimatedBuilder 监听本对象，收到通知重建一次，
  /// 用户设过的字号档位照样立即生效，只是不再拖慢首帧。
  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    _fontLevel = p.getString(_kFont) ?? fontStandard;
    _personalized = p.getBool(_kPersonalized) ?? true;
    _catchPrivacy = p.getBool(_kCatchPrivacy) ?? true;
    _consentAt = p.getString(_kConsent) ?? '';
    notifyListeners();
  }

  Future<void> setFontLevel(String level) async {
    if (level == _fontLevel) return;
    _fontLevel = level;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setString(_kFont, level);
    _report(fontScale: level);
  }

  Future<void> setPersonalized(bool v) async {
    if (v == _personalized) return;
    _personalized = v;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kPersonalized, v);
    _report(personalized: v);
  }

  Future<void> setCatchPrivacy(bool v) async {
    if (v == _catchPrivacy) return;
    _catchPrivacy = v;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kCatchPrivacy, v);
    _report(catchPrivacy: v);
  }

  Future<void> setConsentAt(String iso) async {
    _consentAt = iso;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    if (iso.isEmpty) {
      await p.remove(_kConsent);
    } else {
      await p.setString(_kConsent, iso);
    }
  }

  /// 登录后与服务端对齐（失败静默）
  Future<void> syncFromServer() async {
    if (!ApiConfig.enabled || ApiClient.token == null) return;
    try {
      final s = await SettingsService.fetch();
      var changed = false;
      if (s.personalized != _personalized) {
        _personalized = s.personalized;
        changed = true;
      }
      if (s.catchPrivacy != _catchPrivacy) {
        _catchPrivacy = s.catchPrivacy;
        changed = true;
      }
      if (changed) {
        notifyListeners();
        final p = await SharedPreferences.getInstance();
        await p.setBool(_kPersonalized, _personalized);
        await p.setBool(_kCatchPrivacy, _catchPrivacy);
      }
      // 字体以本机为准：本机从没改过（标准）才跟随服务端，否则把本机值推上去
      if (_fontLevel == fontStandard &&
          s.fontScale != fontStandard &&
          s.fontScale.isNotEmpty) {
        await setFontLevel(s.fontScale);
      } else if (s.fontScale != _fontLevel) {
        _report(fontScale: _fontLevel);
      }
    } catch (_) {
      // 忽略：设置同步失败不影响任何功能
    }
  }

  /// 上报到服务端（不 await，失败静默）
  void _report({
    bool? personalized,
    bool? catchPrivacy,
    String? fontScale,
  }) {
    if (!ApiConfig.enabled || ApiClient.token == null) return;
    SettingsService.save(
      personalized: personalized,
      catchPrivacy: catchPrivacy,
      fontScale: fontScale,
    ).catchError((_) {});
  }
}
