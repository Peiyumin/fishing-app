import 'api_client.dart';
import 'api_config.dart';
import '../utils/json_num.dart';

/// 登录方式配置（v2.1.48）
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

  /// 后台是否开放「本机号码一键登录」
  final bool allowOneKey;

  /// 运营商取号服务是否已配好（AppKey / Secret 齐全）
  final bool oneKeyReady;

  /// 运营商文案，如「天翼账号提供认证服务」
  final String oneKeyCarrier;

  /// 后台是否开放 Apple 登录
  final bool allowApple;

  const AuthConfig({
    this.registerMode = 'both',
    this.allowPhone = true,
    this.allowWechat = false,
    this.wechatReady = false,
    this.passwordLogin = true,
    this.smsDebug = false,
    this.allowOneKey = true,
    this.oneKeyReady = false,
    this.oneKeyCarrier = '',
    this.allowApple = true,
  });

  static const AuthConfig fallback = AuthConfig();

  /// 最近一次拉到的配置（登录页直接用，不用进来先转圈）
  static AuthConfig current = fallback;

  AuthConfig copyWith({
    bool? allowPhone,
    bool? allowWechat,
    bool? wechatReady,
    bool? allowOneKey,
  }) =>
      AuthConfig(
        registerMode: registerMode,
        allowPhone: allowPhone ?? this.allowPhone,
        allowWechat: allowWechat ?? this.allowWechat,
        wechatReady: wechatReady ?? this.wechatReady,
        passwordLogin: passwordLogin,
        smsDebug: smsDebug,
        allowOneKey: allowOneKey ?? this.allowOneKey,
        oneKeyReady: oneKeyReady,
        oneKeyCarrier: oneKeyCarrier,
        allowApple: allowApple,
      );

  factory AuthConfig.fromJson(Map j) => AuthConfig(
        registerMode: (j['registerMode'] ?? 'both').toString(),
        allowPhone: j['allowPhone'] != false,
        allowWechat: j['allowWechat'] == true,
        wechatReady: j['wechatReady'] == true,
        passwordLogin: j['passwordLogin'] != false,
        smsDebug: j['smsDebug'] == true,
        allowOneKey: j['allowOneKey'] != false,
        oneKeyReady: j['oneKeyReady'] == true,
        oneKeyCarrier: (j['oneKeyCarrier'] ?? '').toString(),
        allowApple: j['allowApple'] != false,
      );

  /// 拉取配置；失败不抛错，返回上一次的值（首次则 fallback）
  static Future<AuthConfig> load() async {
    if (!ApiConfig.enabled) return current;
    try {
      final data = jsonMap(await ApiClient.get('/auth/config'));
      current = AuthConfig.fromJson(data);
      return current;
    } catch (_) {
      return current;
    }
  }
}
