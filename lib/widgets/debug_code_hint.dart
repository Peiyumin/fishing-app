import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_theme.dart';

/// 调试模式下的临时验证码提示条（登录页专用，深色底）
///
/// 为什么必须是「常驻一行」而不是只弹 toast：
///   toast 两秒就消失，而且默认位置正好压在验证码输入框上 ——
///   用户反馈的截图里，验证码被那句提示盖住，既看不清也没法再找回来。
///
/// 两种状态：
///   · [code] 为 null（还没点「获取验证码」）→ 先说清这里不发真短信；
///   · [code] 有值 → 把 6 位码大字显示，点一下复制。
///
/// [visible] 由后台 `smsDebug` 决定（后台切到正式短信通道后整块消失）。
class DebugCodeHint extends StatelessWidget {
  const DebugCodeHint({
    super.key,
    required this.visible,
    this.code,
    this.onCopy,
  });

  /// 后台是不是调试模式（不发真短信）
  final bool visible;

  /// 后端回传的临时验证码；null = 还没申请
  final String? code;

  /// 复制成功后的回调（外面弹 toast）
  final void Function(String code)? onCopy;

  /// 供测试定位「已拿到码」的那一版
  static const Key codeKey = Key('auth-debug-code');

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();

    final c = code;

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: c == null ? _explain() : _showCode(c),
    );
  }

  /// 还没发码：解释这个模式在做什么
  Widget _explain() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: AppTheme.accent.withOpacity(.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.accent.withOpacity(.35)),
      ),
      child: Row(
        children: [
          Icon(Icons.bug_report_outlined, size: 15, color: AppTheme.accent),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              '调试模式：不会发真实短信，点「获取验证码」后直接给出临时验证码',
              style: TextStyle(fontSize: 11.5, color: AppTheme.inkMuted, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }

  /// 拿到码：大字显示 + 点一下复制
  Widget _showCode(String c) {
    return GestureDetector(
      key: codeKey,
      behavior: HitTestBehavior.opaque,
      onTap: () async {
        await Clipboard.setData(ClipboardData(text: c));
        onCopy?.call(c);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.accent.withOpacity(.10),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.accent.withOpacity(.45)),
        ),
        child: Row(
          children: [
            Icon(Icons.bug_report_outlined, size: 15, color: AppTheme.accent),
            const SizedBox(width: 7),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('调试模式 · 临时验证码（已自动填入）',
                      style: TextStyle(fontSize: 11, color: AppTheme.inkMuted)),
                  const SizedBox(height: 2),
                  Text(
                    c,
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.accent,
                      letterSpacing: 4,
                    ),
                  ),
                ],
              ),
            ),
            Text('点此复制', style: TextStyle(fontSize: 11, color: AppTheme.inkMuted)),
          ],
        ),
      ),
    );
  }
}
