import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../app_theme.dart';
import 'package:provider/provider.dart';

import '../models/post.dart';
import '../services/api_config.dart';
import '../services/follow_service.dart';
import '../services/post_service.dart';
import '../services/session_provider.dart';
import '../widgets/post_video_player.dart';
import '../widgets/user_avatar.dart';
import 'auth_screen.dart';
import 'user_profile_screen.dart';
import '../widgets/center_toast.dart';

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

  /// 作者关注状态（详情页头像行右侧「加关注」）
  bool _following = false;
  bool _followBusy = false;

  @override
  void initState() {
    super.initState();
    _post = widget.post;
    _following = widget.post.isFollowing;
    _loadComments();
    _trackView();
  }

  /// 加关注 / 取消关注（未登录先去登录）
  Future<void> _toggleFollow() async {
    if (_followBusy || _post.isMe) return;
    final sp = Provider.of<SessionProvider>(context, listen: false);
    if (!sp.isLoggedIn) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const AuthScreen()),
      );
      return;
    }
    setState(() => _followBusy = true);
    try {
      final r = await FollowService.toggleFollow(
        _post.userId,
        _following,
      );
      if (!mounted) return;
      setState(() {
        _following = r.following;
        _post = _post.copyWith(isFollowing: r.following);
      });
      // ignore: use_build_context_synchronously
      CenterToast.show(context, r.following ? '已关注' : '已取消关注');
    } catch (e) {
      if (mounted) CenterToast.show(context, '操作失败：$e');
    } finally {
      if (mounted) setState(() => _followBusy = false);
    }
  }

  /// 等级徽章（淡蓝底 + LV 数字，与社区常见样式一致）
  Widget _levelBadge(int level) {
    final lv = level <= 0 ? 1 : level;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F3FF),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFFB7DBFF), width: 0.8),
      ),
      child: Text(
        'LV$lv',
        style: const TextStyle(
          fontSize: 10.5,
          height: 1.25,
          fontWeight: FontWeight.w700,
          color: Color(0xFF1677FF),
        ),
      ),
    );
  }

  /// 标题下方的作者行：头像 + 昵称 + 等级 + 时间/地区 + 加关注
  Widget _authorRow() {
    final name =
        (_post.username ?? '').trim().isNotEmpty ? _post.username! : '钓友';
    final area = _post.city.trim().isNotEmpty
        ? _post.city.trim()
        : (_post.locationName ?? '').trim();
    final meta = area.isEmpty ? _post.timeAgo : '${_post.timeAgo} · $area';

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
                ],
              ),
              const SizedBox(height: 3),
              Text(
                meta,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 12, color: AppTheme.textSecondary),
              ),
            ],
          ),
        ),
        if (!_post.isMe)
          SizedBox(
            height: 30,
            child: ElevatedButton(
              onPressed: _followBusy ? null : _toggleFollow,
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    _following ? AppTheme.primarySoft : const Color(0xFF1677FF),
                foregroundColor:
                    _following ? AppTheme.textSecondary : Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6)),
              ),
              child: Text(
                _followBusy ? '…' : (_following ? '已关注' : '加关注'),
                style: const TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
            ),
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
                // 标题
                Text(
                  _post.title,
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
                        child: Text(
                          _post.locationName!,
                          overflow: TextOverflow.ellipsis,
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
