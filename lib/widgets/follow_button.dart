import 'package:flutter/material.dart';

import '../models/user_profile.dart';
import '../services/follow_service.dart';
import '../app_theme.dart';
import 'center_toast.dart';

/// 关注 / 已关注 按钮（切换态）
/// 用于动态作者行、用户资料页、粉丝/关注列表
class FollowButton extends StatefulWidget {
  final String userId;
  final bool initialFollowing;
  final bool isMe; // 本人不显示
  final ValueChanged<bool>? onChanged;
  final bool compact; // 小尺寸（列表里用）
  final bool tiny; // 超小尺寸（首页信息流作者行）

  /// 描边样式：未关注时白底 + 主色描边 + 主色文字（信息流作者行大按钮用）
  final bool outline;

  const FollowButton({
    super.key,
    required this.userId,
    this.initialFollowing = false,
    this.isMe = false,
    this.onChanged,
    this.compact = false,
    this.tiny = false,
    this.outline = false,
  });

  @override
  State<FollowButton> createState() => _FollowButtonState();
}

class _FollowButtonState extends State<FollowButton> {
  late bool _following;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _following = widget.initialFollowing;
  }

  Future<void> _toggle() async {
    if (_busy) return;
    setState(() => _busy = true);
    // 乐观更新
    final prev = _following;
    setState(() => _following = !_following);
    try {
      final r = await FollowService.toggleFollow(widget.userId, prev);
      if (!mounted) return;
      setState(() => _following = r.following);
      widget.onChanged?.call(r.following);
    } catch (e) {
      if (!mounted) return;
      setState(() => _following = prev); // 回滚
      final msg = e is FollowNotAvailableException
          ? e.message
          : '操作失败，请稍后再试';
      CenterToast.show(context, msg);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isMe) return const SizedBox.shrink();

    final following = _following;
    // 描边样式（信息流作者行）：比 tiny 大一圈，且未关注时也是白底绿字
    final bool line = widget.outline;
    final double h = line ? 30 : (widget.tiny ? 24 : (widget.compact ? 26 : 32));
    final double fs = line ? 13 : (widget.tiny ? 11 : (widget.compact ? 12 : 13));
    final double hPad = line ? 14 : (widget.tiny ? 10 : (widget.compact ? 12 : 16));
    final double radius =
        line ? 8 : (widget.tiny ? 13 : (widget.compact ? 14 : 16));
    return SizedBox(
      height: h,
      child: OutlinedButton(
        onPressed: _busy ? null : _toggle,
        style: OutlinedButton.styleFrom(
          padding: EdgeInsets.symmetric(horizontal: hPad),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          side: BorderSide(
              color: following ? Colors.grey.shade300 : AppTheme.primary),
          backgroundColor: following
              ? Colors.grey.shade50
              : (line ? Colors.white : AppTheme.primary),
          foregroundColor: following
              ? Colors.grey.shade600
              : (line ? AppTheme.primary : Colors.white),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radius)),
        ),
        child: _busy
            ? SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(following
                      ? Colors.grey.shade600
                      : (line ? AppTheme.primary : Colors.white)),
                ),
              )
            : Text(following ? '已关注' : '关注',
                style: TextStyle(fontSize: fs, fontWeight: FontWeight.w600)),
      ),
    );
  }
}
