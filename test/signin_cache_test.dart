// 签到本地状态的回归测试
//
// 背景（v2.1.17 → v2.1.18 线上真实故障）：
//   `SigninService._cache` 曾被写成 `static const _cache = <String, SigninStatus>{}`。
//   Dart 的 `const {}` 生成的是**不可变 Map**，`_cache['status'] = s` 会抛
//   `UnsupportedError: Cannot modify unmodifiable map`（英文）。
//   后果是：
//     · 签到页永远读不到真实状态 → 连续天数一直是 0（用户："天数不会增加"）；
//     · 点签到时异常冒到 UI → 弹一句英文，看不到「签到成功」。
//   后端其实每次都签到成功了，纯客户端问题。
//
// 这里直接锁住「缓存可写」，防止再被改回去。
import 'package:fishing_app/models/signin.dart';
import 'package:fishing_app/services/signin_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('签到状态缓存必须是可变 Map（否则签到页永远显示 0 天）', () {
    const s = SigninStatus(signedToday: true, streak: 3, total: 9);

    // 不可变 Map 在这里会抛 UnsupportedError
    SigninService.debugCache['status'] = s;

    expect(SigninService.debugCache['status']!.streak, 3);
    expect(SigninService.debugCache['status']!.total, 9);
    expect(SigninService.debugCache['status']!.signedToday, isTrue);

    SigninService.debugCache.remove('status');
    expect(SigninService.debugCache['status'], isNull);
  });

  test('断网兜底状态：7 天奖励 + 5 个每日任务齐备', () {
    final f = SigninService.fallback;
    expect(f.streak, 0);
    expect(f.rewards.length, 7);
    expect(f.tasks.length, 5);
    expect(f.tasks.map((t) => t.key), contains('checkin'));
  });
}
