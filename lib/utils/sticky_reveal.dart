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
/// [barHeight] 顶栏总高度（含状态栏）。
/// 名字顶部滑到「顶栏下沿 + 12」时开始出现，再往上 36px 完全显示。
double stickyInfoOpacity({
  required double nameTop,
  required double barHeight,
}) {
  final t = (barHeight + 12 - nameTop) / 36;
  return t.clamp(0.0, 1.0).toDouble();
}
