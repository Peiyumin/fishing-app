import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../app_theme.dart';
import 'package:provider/provider.dart';

import '../models/post.dart';
import '../services/api_config.dart';
import '../services/post_service.dart';
import '../services/session_provider.dart';
import '../widgets/post_video_player.dart';
import 'auth_screen.dart';

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

  @override
  void initState() {
    super.initState();
    _post = widget.post;
    _loadComments();
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
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('评论失败：$e')));
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
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('操作失败：$e')));
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
          CircleAvatar(
            radius: 16,
            backgroundColor: AppTheme.primarySoft,
            backgroundImage: avatar != null && avatar.isNotEmpty
                ? CachedNetworkImageProvider(
                    ApiConfig.mediaUrl(avatar) ?? avatar)
                : null,
            onBackgroundImageError:
                avatar != null && avatar.isNotEmpty ? (_, __) {} : null,
            child: avatar == null || avatar.isEmpty
                ? const Icon(Icons.person,
                    size: 17, color: AppTheme.textSecondary)
                : null,
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
