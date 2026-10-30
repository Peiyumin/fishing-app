/// 渔获详情页吸顶栏的两个渐显进度（纯函数，方便单测锁行为）
///
/// 拆成两个进度是为了解决「白色栏出现时跟下面内容重叠」：
///  - [stickyShellOpacity]：白栏本体。封面**基本滚出去**才出现，
///    不能再像以前那样「封面还剩 96px 就淡入」，否则白底直接压在封面
///    底部的标题/数量上，看起来就是两块内容糊在一起。
///  - [stickyInfoOpacity]：顶栏里的头像 / 名字 / 关注。要等作者卡里
///    那个名字被顶栏盖住之后才渐显，屏幕上永远只有一个作者名。
library;

/// 白栏本体的不透明度（0 = 不显示，1 = 全白）
///
/// [offset] 当前滚动偏移；[coverHeight] 封面高度。
/// 从「封面剩 24px」开始，再滚 56px 完全出现。
double stickyShellOpacity({
  required double offset,
  required double coverHeight,
}) {
  final t = (offset - (coverHeight - 24)) / 56;
  return t.clamp(0.0, 1.0).toDouble();
}

/// 顶栏作者信息的不透明度
///
/// [nameTop] 作者卡里名字在屏幕上的 y 坐标（全局）；
/// [barHeight] 顶栏总高度（含状态栏）；
/// [shell] 白栏本体的不透明度（[stickyShellOpacity] 的结果）。
///
/// 两条门槛同时满足才显示：
///  ① 名字已经被顶栏盖住（位置条件）；
///  ② 白栏本身**基本不透明**了 —— 否则白栏还是半透明的，卡片上那个名字
///     会从底下透出来，和顶栏的名字叠成一团（还是重叠，只是淡一点）。
double stickyInfoOpacity({
  required double nameTop,
  required double barHeight,
  double shell = 1,
}) {
  // 0.92→1 这一段把名字提上来；shell 已经满时直接给 1，
  // 免得 (1-0.92)/0.08 算出 0.9999999999999994 这种尾巴。
  final gate = shell >= 0.999 ? 1.0 : ((shell - 0.92) / 0.08).clamp(0.0, 1.0);
  final t = ((barHeight + 12 - nameTop) / 36).clamp(0.0, 1.0);
  final v = t * gate;
  return v >= 0.999 ? 1.0 : v;
}
