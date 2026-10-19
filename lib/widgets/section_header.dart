import 'package:flutter/material.dart';

import '../app_theme.dart';

/// 统一分区标题：左侧强调竖条 + 标题 + 可选的「更多/操作」链接
/// 用于首页「实时天气 / 附近钓点 / 钓友动态」等各区块，保证视觉一致。
class SectionHeader extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  final EdgeInsetsGeometry padding;

  const SectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
    this.padding =
        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Container(
            width: 4,
            height: 16,
            decoration: BoxDecoration(
              color: AppTheme.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
              letterSpacing: 0.3,
            ),
          ),
          const Spacer(),
          if (actionLabel != null && onAction != null)
            InkWell(
              onTap: onAction,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Row(
                  children: [
                    // 文案只写链接名（如「更多」「7天预报」），箭头统一由图标渲染，
                    // 避免「更多 >>」变成「更多 >> ›」的重复箭头
                    Text(actionLabel!.replaceAll(RegExp(r'\s*>+\s*$'), ''),
                        style: const TextStyle(
                            fontSize: 13, color: AppTheme.accent)),
                    const Icon(Icons.chevron_right,
                        size: 16, color: AppTheme.accent),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
