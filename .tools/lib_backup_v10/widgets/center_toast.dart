import 'package:flutter/material.dart';

import '../app_theme.dart';

/// 屏幕中间弹出的轻提示
///
/// 为什么不用 SnackBar：
/// SnackBar 从底部升起，会把底部导航 / 中间凸起的发布按钮往上顶，
/// 布局看起来像错位了。居中浮层不参与布局，不挤任何控件。
class CenterToast {
  /// 当前正在显示的浮层，避免连点时叠出一堆
  static OverlayEntry? _entry;

  /// 显示一条提示；[icon] 可选（成功/警告等场景）
  static void show(
    BuildContext context,
    String message, {
    IconData? icon,
    Duration duration = const Duration(milliseconds: 1600),
  }) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    dismiss();

    final entry = OverlayEntry(
      builder: (_) => _ToastWidget(message: message, icon: icon),
    );
    _entry = entry;
    overlay.insert(entry);

    Future.delayed(duration, () {
      if (_entry == entry) dismiss();
    });
  }

  /// 立刻移除当前提示
  static void dismiss() {
    _entry?.remove();
    _entry = null;
  }
}

class _ToastWidget extends StatefulWidget {
  final String message;
  final IconData? icon;
  const _ToastWidget({required this.message, this.icon});

  @override
  State<_ToastWidget> createState() => _ToastWidgetState();
}

class _ToastWidgetState extends State<_ToastWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  )..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: FadeTransition(
          opacity: _c,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.94, end: 1).animate(
              CurvedAnimation(parent: _c, curve: Curves.easeOut),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 280),
              child: Material(
                color: Colors.transparent,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xF016241E), // textPrimary 96% 不透明
                    borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                    boxShadow: AppTheme.softShadow,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.icon != null) ...[
                        Icon(widget.icon, color: Colors.white, size: 18),
                        const SizedBox(width: 8),
                      ],
                      Flexible(
                        child: Text(
                          widget.message,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
