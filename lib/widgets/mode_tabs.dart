import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models/home_mode.dart';

/// 首页「渔报」标题下面的钓法分类条：台钓 / 路亚 / 钓场 / 海钓（v2.1.86）
///
/// 视觉约束（这几个值都是踩过的点）：
///   · 它长在近黑渐变顶栏里，所以文字只能走白系的透明度层级，
///     不能吃 `AppTheme.textXxx`（那是浅底页面的深色字，压上去直接看不见）；
///   · 选中态不能只靠颜色区分 —— 底下加一条 3px 的荧光绿短线（主题 accent），
///     色弱用户也能看出「当前是哪一个」；
///   · 高度 38：四个字一段文字，38 才有 44pt 手感又不把顶栏撑太高
///     （顶栏 62 + 这里 38 = 100，还没到一屏的 1/8）。
class ModeTabs extends StatelessWidget {
  final HomeMode mode;
  final ValueChanged<HomeMode>? onChanged;

  static const double height = 38;

  const ModeTabs({super.key, required this.mode, this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Row(
        children: [
          for (final m in HomeMode.values)
            Expanded(
              child: _tab(context, m),
            ),
        ],
      ),
    );
  }

  Widget _tab(BuildContext context, HomeMode m) {
    final sel = m == mode;
    // ★ 必须基于环境样式 copyWith，不能新建一个「干净」的 TextStyle：
    //   AnimatedDefaultTextStyle 会**替换**子树的 DefaultTextStyle，
    //   新建样式就等于把主题的字体族丢掉 —— 真机上会退到系统默认字体
    //   （截图/测试环境甚至直接退到 Ahem，中文全变方块）。
    final base = DefaultTextStyle.of(context).style;
    return Semantics(
      button: true,
      selected: sel,
      label: '${m.label}${sel ? '，已选中' : ''}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onChanged == null || sel ? null : () => onChanged!(m),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 160),
              style: base.copyWith(
                fontSize: sel ? 14 : 13,
                fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                // 未选中的字要能看清但明显退后：白 55% ≈ 在近黑上足够读，
                // 而 30% 那种「幽灵按钮」在户外强光下基本看不见
                color: sel ? Colors.white : Colors.white.withOpacity(0.55),
                letterSpacing: 0.5,
              ),
              child: Text(m.label),
            ),
            const SizedBox(height: 5),
            // 选中指示条：不选时不占高度（否则切换会整条上下跳 3px）
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: sel ? 20 : 0,
              height: 3,
              decoration: BoxDecoration(
                color: AppTheme.accent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
