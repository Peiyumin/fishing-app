import 'package:flutter/foundation.dart';

/// 全局刷新信号（轻量事件总线）
///
/// 解决的场景：发布页是独立路由（不在底部导航里），发布成功后首页
/// 不会重建，用户回到首页看不到刚发的渔获。这里用一个全局计数器广播
/// 「信息流变了」，首页监听后就地重新拉取，不需要杀掉 App 重开。
class RefreshBus {
  RefreshBus._();

  /// 信息流（首页动态 / 渔获）刷新计数
  static final ValueNotifier<int> feedTick = ValueNotifier<int>(0);

  /// 钓点刷新计数（新增钓点 / 报错后让列表更新）
  static final ValueNotifier<int> spotTick = ValueNotifier<int>(0);

  /// 我的资料刷新计数（积分兑换、编辑资料后刷新「我的」页）
  static final ValueNotifier<int> profileTick = ValueNotifier<int>(0);

  /// 首页刷新计数（v2.1.89）
  ///
  /// 首页的「下拉刷新」已经取消（用户要求：不要手动刷新），改为在
  /// **回到首页**这个动作上自动刷一次 —— 点底部「首页」、或从别的 Tab
  /// 切回来时由 MainShell 打一枪，首页收到就静默重拉一遍数据。
  static final ValueNotifier<int> homeTick = ValueNotifier<int>(0);

  static void bumpFeed() => feedTick.value++;

  static void bumpSpots() => spotTick.value++;

  static void bumpProfile() => profileTick.value++;

  static void bumpHome() => homeTick.value++;
}
