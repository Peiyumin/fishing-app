import 'package:flutter/material.dart';

import '../app_theme.dart';

/// 全站通用页面件（v2.1.59）
///
/// 为什么要有这个文件：
/// 在 2.1.58 之前，每个页面都是自己拼 Container + BoxDecoration，
/// 于是同一件事在不同页面长得不一样 —— 卡片的圆角有 10/12/14/16/20/24 六种，
/// 空状态有「裸图标 + 一行灰字」「大白卡 + 图标」两种，分组标题有的 11px 有的 15px。
/// 单看每一页都还行，连着翻五页就会觉得「不是一个 App」。
///
/// 这里只放**跨页复用**的四种件，且全部只取 [AppTheme] 的色板与尺寸，
/// 不允许出现裸色值（`test/theme_palette_test.dart` 会拦）。

/// 统一白卡：白底 + radiusLg + 1px 描边（不用阴影，阴影在冷灰底上会发脏）
class UiCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? margin;

  const UiCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    final body = padding == null
        ? child
        : Padding(padding: padding!, child: child);
    return Container(
      margin: margin,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(color: AppTheme.border),
      ),
      child: onTap == null
          ? body
          : Material(
              color: Colors.transparent,
              child: InkWell(onTap: onTap, child: body),
            ),
    );
  }
}

/// 分组小标题（设置页那种：小字号、全大写字母间距、灰）
///
/// 分组标题只做「分组的标签」，不该和内容标题抢视觉重量，
/// 所以固定 12/w600/textTertiary，且不允许调用方改字号。
class UiSectionTitle extends StatelessWidget {
  final String title;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  const UiSectionTitle(
    this.title, {
    super.key,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(4, 20, 4, 8),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 12,
                height: 1.2,
                fontWeight: FontWeight.w600,
                color: AppTheme.textTertiary,
                letterSpacing: 0.3,
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// 统一空状态
///
/// 旧版每页各写一套：有的 80px 灰图标 + 裸文字，有的塞在一张大白卡里，
/// 文案一会儿「暂无数据」一会儿「这里还没有内容，下拉刷新试试」。
/// 现在统一成「浅底圆角图标 + 标题 + 一行说明 + 可选按钮」。
class UiEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? desc;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// 卡片内部使用（内边距更小、图标更小）
  final bool compact;

  const UiEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.desc,
    this.actionLabel,
    this.onAction,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final iconBox = compact ? 56.0 : 72.0;
    return Padding(
      padding: EdgeInsets.symmetric(
          horizontal: 24, vertical: compact ? 22 : 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: iconBox,
            height: iconBox,
            decoration: BoxDecoration(
              // 白底 + 细边：页面底色本身就是冷灰，淡灰底会"糊"在背景里
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(compact ? 18 : 24),
              border: Border.all(color: AppTheme.border),
            ),
            alignment: Alignment.center,
            child: Icon(icon,
                size: compact ? 24 : 30, color: AppTheme.textTertiary),
          ),
          SizedBox(height: compact ? 12 : 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
              height: 1.3,
            ),
          ),
          if (desc != null && desc!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              desc!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.45,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
          if (actionLabel != null && onAction != null) ...[
            SizedBox(height: compact ? 14 : 18),
            SizedBox(
              height: compact ? 34 : 38,
              child: ElevatedButton(
                onPressed: onAction,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                  ),
                  textStyle: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600),
                ),
                child: Text(actionLabel!),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 标签语气：一屏里最多三种，别按类别乱上色
enum UiTagTone {
  /// 中性（默认）：浅灰底 + 次级文字
  neutral,

  /// 强调：淡黄绿底 + 深黄绿字（「推荐」「新手友好」这类正向标签）
  accent,

  /// 实心近黑（极少用，一屏最多一个）
  solid,

  /// 警示（价格、风险提示）
  warn,
}

/// 统一小标签
class UiTag extends StatelessWidget {
  final String text;
  final UiTagTone tone;
  final IconData? icon;

  const UiTag(this.text,
      {super.key, this.tone = UiTagTone.neutral, this.icon});

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color fg;
    switch (tone) {
      case UiTagTone.accent:
        bg = AppTheme.accentLight;
        fg = AppTheme.accentDark;
        break;
      case UiTagTone.solid:
        bg = AppTheme.primary;
        fg = Colors.white;
        break;
      case UiTagTone.warn:
        bg = AppTheme.warningLight;
        fg = AppTheme.warning;
        break;
      case UiTagTone.neutral:
        bg = AppTheme.primarySoft;
        fg = AppTheme.textSecondary;
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 10, color: fg),
            const SizedBox(width: 2),
          ],
          Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 10, height: 1.3, color: fg, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}
