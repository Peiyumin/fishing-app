import 'api_client.dart';
import 'api_config.dart';

/// 登录方式配置（v2.1.46）
///
/// 由后台「运营配置 → 注册与登录方式」下发，App **每次打开登录页都拉一次**，
/// 所以后台改完不用发版就能生效。
///
/// 后端不可达时用 [fallback]：只给手机号（+ 现有密码登录），
/// 绝不默认放微信 —— 微信参数没配好时放出来只会让用户点了没反应。
class AuthConfig {
  /// phone / wechat / both
  final String registerMode;
  final bool allowPhone;
  final bool allowWechat;
  final bool wechatReady;
  final bool passwordLogin;

  /// 短信是调试模式（未接真实短信通道），验证码会随接口一起返回
  final bool smsDebug;

  const AuthConfig({
    this.registerMode = 'both',
    this.allowPhone = true,
    this.allowWechat = false,
    this.wechatReady = false,
    this.passwordLogin = true,
    this.smsDebug = false,
  });

  static const AuthConfig fallback = AuthConfig();

  /// 最近一次拉到的配置（登录页直接用，不用进来先转圈）
  static AuthConfig current = fallback;

  AuthConfig copyWith({bool? allowPhone, bool? allowWechat, bool? wechatReady}) =>
      AuthConfig(
        registerMode: registerMode,
        allowPhone: allowPhone ?? this.allowPhone,
        allowWechat: allowWechat ?? this.allowWechat,
        wechatReady: wechatReady ?? this.wechatReady,
        passwordLogin: passwordLogin,
        smsDebug: smsDebug,
      );

  factory AuthConfig.fromJson(Map j) => AuthConfig(
        registerMode: (j['registerMode'] ?? 'both').toString(),
        allowPhone: j['allowPhone'] != false,
        allowWechat: j['allowWechat'] == true,
        wechatReady: j['wechatReady'] == true,
        passwordLogin: j['passwordLogin'] != false,
        smsDebug: j['smsDebug'] == true,
      );

  /// 拉取配置；失败不抛错，返回上一次的值（首次则 fallback）
  static Future<AuthConfig> load() async {
    if (!ApiConfig.enabled) return current;
    try {
      final data = await ApiClient.get('/auth/config') as Map;
      current = AuthConfig.fromJson(data);
      return current;
    } catch (_) {
      return current;
    }
  }
}
