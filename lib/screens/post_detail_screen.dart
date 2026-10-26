import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../widgets/emoji_panel.dart';
import 'package:provider/provider.dart';

import '../models/badge.dart';
import '../models/post.dart';
import '../services/api_config.dart';
import '../services/badge_hub.dart';
import '../services/post_service.dart';
import '../services/session_provider.dart';
import '../widgets/location_label.dart';
import '../widgets/post_video_player.dart';
import '../widgets/user_avatar.dart';
import 'auth_screen.dart';
import 'user_profile_screen.dart';
import 'publish_catch_screen.dart';
import '../services/refresh_bus.dart';
import '../widgets/center_toast.dart';
import '../widgets/follow_button.dart';

/// 动态详情：大图 + 正文 + 评论区 + 发表评论
class PostDetailScreen extends StatefulWidget {
  final Post post;
  const PostDetailScreen({super.key, required this.post});

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  late Post _post;
  List<Map<String, dynamic>> _comments = [];
  final _ctrl = TextEditingController();
  bool _loading = true;

  /// 作者关注状态（详情页作者行右侧「关注」，交给 FollowButton 维护）
  bool _following = false;

  @override
  void initState() {
    super.initState();
    _post = widget.post;
    _following = widget.post.isFollowing;
    _loadComments();
    _trackView();
  }

  /// 编辑自己的动态：进入发布页（预填），返回 true 表示已保存，回列表刷新
  Future<void> _edit() async {
    final updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PublishCatchScreen(existing: _post),
      ),
    );
    if (updated == true && mounted) {
      RefreshBus.bumpFeed();
      Navigator.of(context).pop(true);
    }
  }

  /// 删除自己的动态（后端二次校验作者身份）
  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('删除动态'),
        content: const Text('确定删除这条动态吗？删除后他人与自己的列表都不再显示，且无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await PostService.deletePost(_post.id);
      if (!mounted) return;
      RefreshBus.bumpFeed();
      CenterToast.show(context, '已删除');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) CenterToast.show(context, '删除失败：$e');
    }
  }

  /// 等级标签（绿底绿字，与 App 主色一致）
  Widget _levelBadge(int level) {
    final lv = level <= 0 ? 1 : level;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: AppTheme.primaryLight,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppTheme.primaryBorder, width: 0.8),
      ),
      child: Text(
        'LV$lv',
        style: const TextStyle(
          fontSize: 10.5,
          height: 1.25,
          fontWeight: FontWeight.w700,
          color: AppTheme.primary,
        ),
      ),
    );
  }

  /// 等级后面的徽章（最多 3 枚）。数据来源同首页卡片：
  /// 动态自带就用自带的，否则由 BadgeHub 按作者 id 批量拉。
  Widget _authorBadges() {
    BadgeHub.warm([_post.userId]);
    return ValueListenableBuilder<int>(
      valueListenable: BadgeHub.revision,
      builder: (_, __, ___) {
        final badges = _post.badges.isNotEmpty
            ? _post.badges.take(3).toList()
            : BadgeHub.of(_post.userId).take(3).toList();
        if (badges.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(left: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final b in badges)
                Padding(
                  padding: const EdgeInsets.only(right: 3),
                  child: _badgeChip(b),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _badgeChip(BadgeItem b) {
    final url = b.isImage ? ApiConfig.mediaUrl(b.icon) : null;
    final tint = _hexColor(b.color) ?? AppTheme.primary;
    return Tooltip(
      message: b.name,
      child: Container(
        width: 17,
        height: 17,
        decoration: BoxDecoration(
          color: tint.withOpacity(0.12),
          borderRadius: BorderRadius.circular(5),
        ),
        alignment: Alignment.center,
        child: url != null && url.isNotEmpty
            ? ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Image.network(
                  url,
                  width: 17,
                  height: 17,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      Icon(Icons.military_tech, size: 13, color: tint),
                ),
              )
            : (b.icon.isNotEmpty
                ? Text(b.icon, style: const TextStyle(fontSize: 11, height: 1))
                : Icon(Icons.military_tech, size: 13, color: tint)),
      ),
    );
  }

  Color? _hexColor(String s) {
    var v = s.trim().replaceAll('#', '');
    if (v.length == 3) {
      v = v.split('').map((c) => '$c$c').join();
    }
    if (v.length != 6) return null;
    final n = int.tryParse(v, radix: 16);
    if (n == null) return null;
    return Color(0xFF000000 | n);
  }

  /// 标题下方的作者行：头像 + 昵称 + 等级 + 时间/地区 + 加关注
  Widget _authorRow() {
    final name =
        (_post.username ?? '').trim().isNotEmpty ? _post.username! : '钓友';
    final area = _post.city.trim().isNotEmpty
        ? _post.city.trim()
        : (_post.locationName ?? '').trim();

    return Row(
      children: [
        InkWell(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
                builder: (_) => UserProfileScreen(userId: _post.userId)),
          ),
          borderRadius: BorderRadius.circular(30),
          child: UserAvatar(
            url: ApiConfig.mediaUrl(_post.avatarUrl),
            userId: _post.userId,
            radius: 21,
            vipLevel: _post.authorVip,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  _levelBadge(_post.userLevel),
                  _authorBadges(),
                ],
              ),
              const SizedBox(height: 3),
              // 「16小时前 · 城市名」；area 若是历史坐标则异步逆地编码成中文地名
              Row(
                children: [
                  Text(
                    _post.timeAgo,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12, color: AppTheme.textSecondary),
                  ),
                  if (area.isNotEmpty) ...[
                    const Text(
                      ' · ',
                      style: TextStyle(
                          fontSize: 12, color: AppTheme.textSecondary),
                    ),
                    Flexible(
                      child: LocationLabel(
                        raw: area,
                        style: const TextStyle(
                            fontSize: 12, color: AppTheme.textSecondary),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        if (!_post.isMe && ApiConfig.enabled)
          // 与首页信息流作者行同一个组件（绿底白字「关注」），不再用蓝色加关注
          FollowButton(
            userId: _post.userId,
            tiny: true,
            initialFollowing: _following,
            onChanged: (v) => _following = v,
          ),
      ],
    );
  }

  /// 浏览量 +1（热门/推荐算法依据；失败静默）
  Future<void> _trackView() async {
    await PostService.trackView(_post.id);
    if (mounted) {
      setState(() => _post = _post.copyWith(viewCount: _post.viewCount + 1));
    }
  }

  Future<void> _loadComments() async {
    try {
      final c = await PostService.fetchComments(_post.id);
      if (mounted) setState(() => _comments = c);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _send() async {
    final sp = Provider.of<SessionProvider>(context, listen: false);
    if (!sp.isLoggedIn) {
      // 未登录直接带去登录页，登录回来还能接着评
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const AuthScreen()),
      );
      return;
    }
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    try {
      await PostService.addComment(_post.id, text);
      _ctrl.clear();
      setState(() => _post = _post.copyWith(commentCount: _post.commentCount + 1));
      await _loadComments();
    } catch (e) {
      if (!mounted) return;
      CenterToast.show(context, '评论失败：$e');
    }
  }

  bool _likeBusy = false;

  /// 点赞 / 取消点赞（未登录先去登录）
  Future<void> _toggleLike() async {
    if (_likeBusy) return;
    final sp = Provider.of<SessionProvider>(context, listen: false);
    if (!sp.isLoggedIn) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const AuthScreen()),
      );
      return;
    }
    setState(() => _likeBusy = true);
    try {
      final nowLiked = await PostService.toggleLike(_post.id, _post.likedByMe);
      if (!mounted) return;
      setState(() {
        _post = _post.copyWith(
          likedByMe: nowLiked,
          likeCount: _post.likeCount + (nowLiked ? 1 : -1),
        );
      });
    } catch (e) {
      if (mounted) {
        CenterToast.show(context, '操作失败：$e');
      }
    } finally {
      if (mounted) setState(() => _likeBusy = false);
    }
  }

  /// 正文图片：单张按原比例，多张纵向排列；加载失败有占位
  Widget _bodyImage(String url) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        child: CachedNetworkImage(
          imageUrl: url,
          fit: BoxFit.fitWidth,
          fadeInDuration: const Duration(milliseconds: 180),
          placeholder: (_, __) => const AspectRatio(
            aspectRatio: 4 / 3,
            child: ColoredBox(
              color: AppTheme.primarySoft,
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 1.8, color: AppTheme.primaryBorder),
                ),
              ),
            ),
          ),
          errorWidget: (_, __, ___) => const AspectRatio(
            aspectRatio: 4 / 3,
            child: ColoredBox(
              color: AppTheme.primarySoft,
              child: Center(
                child: Icon(Icons.broken_image_outlined,
                    size: 28, color: AppTheme.textSecondary),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 单条评论
  Widget _commentTile(Map<String, dynamic> c) {
    final name = (c['user_nickname'] as String?) ?? '钓友';
    final avatar = c['user_avatar'] as String?;
    final content = (c['content'] as String?) ?? '';
    final createdAt = (c['created_at'] as String?) ?? '';
    final time = createdAt.isEmpty
        ? ''
        : (createdAt.length >= 16 ? createdAt.substring(5, 16) : createdAt);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          UserAvatar(
            url: ApiConfig.mediaUrl(avatar),
            userId: c['user_id'] as String?,
            radius: 16,
            vipLevel: (c['user_vip'] as num?)?.toInt() ?? 0,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textPrimary)),
                    ),
                    if (time.isNotEmpty)
                      Text(time,
                          style: const TextStyle(
                              fontSize: 11, color: AppTheme.textSecondary)),
                  ],
                ),
                const SizedBox(height: 3),
                Text(content,
                    style: const TextStyle(
                        fontSize: 14,
                        height: 1.5,
                        color: AppTheme.textPrimary)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('动态详情'),
        flexibleSpace: Container(
          decoration: const BoxDecoration(gradient: AppTheme.headerGradient),
        ),
        actions: [
          if (_post.isMe) ...[
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: '编辑',
              onPressed: _edit,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: '删除',
              onPressed: _delete,
            ),
          ],
        ],
      ),
      body: ListView(
        children: [
          // ── 标题 → 分割线 → 正文 → 图片 → 定位 + 评论 + 点赞 ──
          Container(
            color: AppTheme.surface,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 标题：渔获统一「今日鱼获分享」（与首页完全一致）
                if (_post.isCatch) ...[
                  Row(
                    children: [
                      Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          gradient: AppTheme.brandGradient,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.set_meal,
                            size: 16, color: Colors.white),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        '今日鱼获分享',
                        style: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w800,
                          height: 1.25,
                          letterSpacing: 0.3,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: 52,
                    height: 3,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                          colors: [AppTheme.primary, AppTheme.accent]),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  if (_post.catchSummary.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryLight,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.phishing,
                              size: 14, color: AppTheme.primary),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              _post.catchSummary,
                              style: const TextStyle(
                                fontSize: 14,
                                height: 1.35,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.primaryDark,
                              ),
                            ),
                          ),
                          if (_post.catchTotal > 0) ...[
                            const SizedBox(width: 8),
                            Text(
                              '共 ${_post.catchTotal} 条',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ] else
                  Text(
                    _post.displayTitle,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      height: 1.35,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                const SizedBox(height: 12),
                // 作者：头像 + 昵称 + 等级 + 时间/地区 + 加关注
                _authorRow(),
                const SizedBox(height: 12),
                // 标题下的分割线
                const Divider(height: 1, thickness: 1, color: AppTheme.divider),
                const SizedBox(height: 12),
                // 正文
                if (_post.body != null && _post.body!.isNotEmpty) ...[
                  Text(
                    _post.body!,
                    style: const TextStyle(
                      fontSize: 15,
                      height: 1.7,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                // 媒体
                if (_post.isVideo)
                  PostVideoPlayer(url: _post.videoUrl!, height: 300)
                else if (_post.imageUrls.isNotEmpty)
                  ..._post.imageUrls.map(_bodyImage),
                const SizedBox(height: 2),
                // 底部信息行：定位 + 评论 + 点赞
                const Divider(height: 1, thickness: 1, color: AppTheme.divider),
                const SizedBox(height: 10),
                Row(
                  children: [
                    if (_post.locationName != null &&
                        _post.locationName!.isNotEmpty) ...[
                      const Icon(Icons.location_on,
                          size: 16, color: AppTheme.textSecondary),
                      const SizedBox(width: 3),
                      Flexible(
                        child: LocationLabel(
                          raw: _post.locationName!,
                          style: const TextStyle(
                              fontSize: 13, color: AppTheme.textSecondary),
                        ),
                      ),
                    ],
                    const Spacer(),
                    // 浏览量
                    Row(
                      children: [
                        const Icon(Icons.visibility_outlined,
                            size: 16, color: AppTheme.textSecondary),
                        const SizedBox(width: 4),
                        Text('${_post.viewCount}',
                            style: const TextStyle(
                                fontSize: 13, color: AppTheme.textSecondary)),
                      ],
                    ),
                    const SizedBox(width: 20),
                    // 评论
                    Row(
                      children: [
                        const Icon(Icons.chat_bubble_outline,
                            size: 17, color: AppTheme.textSecondary),
                        const SizedBox(width: 4),
                        Text('${_post.commentCount}',
                            style: const TextStyle(
                                fontSize: 13, color: AppTheme.textSecondary)),
                      ],
                    ),
                    const SizedBox(width: 20),
                    // 点赞（可点，显示数量）
                    InkWell(
                      onTap: _toggleLike,
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 4),
                        child: Row(
                          children: [
                            Icon(
                              _post.likedByMe
                                  ? Icons.favorite
                                  : Icons.favorite_border,
                              size: 17,
                              color: _post.likedByMe
                                  ? AppTheme.danger
                                  : AppTheme.textSecondary,
                            ),
                            const SizedBox(width: 4),
                            Text('${_post.likeCount}',
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: _post.likedByMe
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                    color: _post.likedByMe
                                        ? AppTheme.danger
                                        : AppTheme.textSecondary)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // 评论区
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: Row(
              children: [
                const Text('评论',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary)),
                const SizedBox(width: 6),
                Text('${_post.commentCount}',
                    style: const TextStyle(
                        fontSize: 13, color: AppTheme.textSecondary)),
              ],
            ),
          ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_comments.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Center(
                child: Text('还没有评论，来抢沙发',
                    style: TextStyle(color: AppTheme.textSecondary)),
              ),
            )
          else
            ..._comments.map((c) => _commentTile(c)),
        ],
      ),
      // 底部评论输入
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: AppTheme.surface,
          border: Border(top: BorderSide(color: AppTheme.divider)),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    decoration: InputDecoration(
                      hintText: '说点什么…',
                      isDense: true,
                      filled: true,
                      fillColor: AppTheme.primarySoft,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(AppTheme.radiusPill),
                        borderSide: BorderSide.none,
                      ),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.emoji_emotions_outlined,
                            size: 19, color: AppTheme.textSecondary),
                        tooltip: '表情',
                        onPressed: () => showEmojiSheet(context, _ctrl),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.send, color: AppTheme.primary),
                  onPressed: _send,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
