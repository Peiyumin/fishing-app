import 'dart:async';

import 'package:flutter/services.dart';

/// 本机号码一键登录的能力探测（v2.1.48）
///
/// ## 为什么不能「客户端读 SIM 号就直接登录」
///
/// 安卓的 `TelephonyManager.getLine1Number()` 拿到的是运营商写在 SIM 卡里的
/// 号码，它**只是一个本地字符串**，服务端无法验证「这台手机现在用的就是这张卡」。
/// 如果后端接受客户端上报的手机号直接登录，任何人填别人的号码就能登进别人账号
/// —— 这是给全站开后门。所以真正的「一键登录」只能走运营商网关取号：
/// 蜂窝网络下由运营商侧识别本机号码，下发一个**一次性 token**，服务端拿
/// token 去服务商（阿里云号码认证 / 极光认证 / Mob 秒验）换真实号码。
///
/// 因此这里的边界是：
///   · [available] = 本机是否已集成运营商取号 SDK（未接就是 false）；
///   · [phone]     = 尽力读到的 SIM 卡号码，**只用来预填手机号**，
///                   绝不用于免验证登录；
///   · [token]     = 运营商取号凭证，只有它能换到可信号码。
///
/// 未接 SDK 时界面照设计稿显示，但点按钮会明确提示未开通，并自动降级为
/// 「用这个号码接收验证码」—— 用户最多多点一次「获取验证码」，不会卡死。
class OneKeyProbe {
  /// 是否已集成运营商取号 SDK（能拿到可信 token）
  final bool available;

  /// SIM 卡里读到的号码（多数国产 ROM 返回空，属正常）
  final String phone;

  /// 展示用带星号号码，如 199****3288
  final String masked;

  /// 不可用原因：not_integrated / not_supported / no_sim / no_permission /
  /// no_cellular / timeout / error
  final String reason;

  const OneKeyProbe({
    this.available = false,
    this.phone = '',
    this.masked = '',
    this.reason = 'not_integrated',
  });

  static const OneKeyProbe none = OneKeyProbe();

  bool get hasPhone => phone.length == 11;
}

class OneKeyLoginService {
  static const MethodChannel _ch = MethodChannel('fishing/onekey');

  /// ★ 必须带超时。原生通道在某些机型上「既不返回也不报错」，
  ///   挡住登录页首帧就是一直转圈 —— 比功能不可用更糟。
  static const Duration _probeTimeout = Duration(milliseconds: 900);

  /// 最近一次探测结果（登录页直接用，避免每帧都打通道）
  static OneKeyProbe last = OneKeyProbe.none;

  /// 把 19912343288 变成 199****3288
  static String mask(String phone) {
    final p = phone.replaceAll(RegExp(r'\D'), '');
    if (p.length != 11) return '';
    return '${p.substring(0, 3)}****${p.substring(7)}';
  }

  /// 探测本机能力。任何异常都吞掉并返回「不可用」，绝不抛出。
  static Future<OneKeyProbe> probe() async {
    try {
      final r = await _ch
          .invokeMethod<Map<Object?, Object?>>('probe')
          .timeout(_probeTimeout);
      if (r == null) {
        last = const OneKeyProbe(reason: 'not_integrated');
        return last;
      }
      final phone = (r['phone'] ?? '').toString();
      final masked = (r['masked'] ?? '').toString();
      last = OneKeyProbe(
        available: r['available'] == true,
        phone: phone,
        masked: masked.isNotEmpty ? masked : mask(phone),
        reason: (r['reason'] ?? '').toString(),
      );
    } on MissingPluginException {
      last = const OneKeyProbe(reason: 'not_integrated');
    } on PlatformException catch (e) {
      last = OneKeyProbe(reason: e.code);
    } on TimeoutException {
      last = const OneKeyProbe(reason: 'timeout');
    } catch (_) {
      last = const OneKeyProbe(reason: 'error');
    }
    return last;
  }

  /// 取运营商取号 token（服务端拿它换真实号码）
  ///
  /// 未接 SDK 时原生会抛 `not_integrated`，调用方按原因给提示。
  static Future<String> fetchToken() async {
    try {
      final t = await _ch
          .invokeMethod<String>('token')
          .timeout(const Duration(seconds: 12));
      return (t ?? '').trim();
    } on MissingPluginException {
      throw const OneKeyException('not_integrated', '当前版本未内置运营商取号');
    } on PlatformException catch (e) {
      throw OneKeyException(e.code, e.message ?? '取号失败');
    } on TimeoutException {
      throw const OneKeyException('timeout', '取号超时，请检查是否在用移动网络');
    }
  }

  /// 把失败原因翻成人话
  static String hint(String reason) {
    switch (reason) {
      case 'not_integrated':
        return '本机号码一键登录需要运营商取号服务，当前版本还没开通，请用短信验证码登录';
      case 'not_supported':
        return 'iPhone 不支持读取本机号码，请用短信验证码登录';
      case 'no_permission':
        return '没有电话权限，读不到本机号码，请用短信验证码登录';
      case 'no_sim':
        return '没检测到手机卡，请用短信验证码登录';
      case 'no_cellular':
        return '请关闭 WiFi、用移动网络再试，或用短信验证码登录';
      case 'not_configured':
        return '后台还没配置运营商取号服务，请用短信验证码登录';
      case 'timeout':
        return '取号超时，请检查移动网络后重试，或用短信验证码登录';
      case 'cancel':
        return '已取消一键登录';
      default:
        return '本机号码一键登录暂不可用，请用短信验证码登录';
    }
  }
}

class OneKeyException implements Exception {
  final String code;
  final String message;
  const OneKeyException(this.code, this.message);

  @override
  String toString() => message;
}
