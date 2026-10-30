import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../models/article.dart';
import '../models/user_profile.dart';
import '../services/api_config.dart';
import '../services/content_service.dart';
import '../services/follow_service.dart';
import '../services/session_provider.dart';
import '../widgets/ad_slot.dart';
import '../widgets/center_toast.dart';
import '../widgets/follow_button.dart';
import '../widgets/user_avatar.dart';
import 'auth_screen.dart';
import 'publish_article_screen.dart';
import 'user_profile_screen.dart';

/// 文章详情（v2.1.55 按用户给的版式重排）
///
/// 顺序：
///   标题 → 头像·名字·城市（右侧关注）→ 日期 → 分割线 → 正文 →
///   点赞 → 分割线 → 广告位 → 相关阅读（10 篇）→ 我也要投稿
///
/// 列表接口不返回正文（避免列表响应变大），这里按 id 再拉一次拿 content；
/// 作者的头像 / 关注态单独拉一次 `/users/:id`（列表只给了昵称）。
class ArticleDetailScreen extends StatefulWidget {
  final Article article;
  const ArticleDetailScreen({super.key, required this.article});

  @override
  State<ArticleDetailScreen> createState() => _ArticleDetailScreenState();
}

class _ArticleDetailScreenState extends State<ArticleDetailScreen> {
  late Article _a = widget.article;
  bool _loading = true;

  /// 作者资料（头像 / 是否已关注）
  UserProfile? _author;

  /// 点赞态（本地乐观更新，服务端回来再对齐）
  bool _liked = false;
  int _likeCount = 0;
  bool _likeBusy = false;

  /// 相关阅读（同分类优先，凑满 10 篇）
  List<Article> _related = const [];

  @override
  void initState() {
    super.initState();
    _liked = _a.liked;
    _likeCount = _a.likeCount;
    _load();
  }

  Future<void> _load() async {
    final full = await ContentService.fetchArticle(widget.article.id);
    if (!mounted) return;
    setState(() {
      if (full != null) {
        _a = full;
        _liked = full.liked;
        _likeCount = full.likeCount;
      }
      _loading = false;
    });
    _loadAuthor();
    _loadRelated();
  }

  Future<void> _loadAuthor() async {
    final id = _a.authorId.trim();
    if (id.isEmpty || !ApiConfig.enabled) return;
    try {
      final p = await FollowService.fetchProfile(id);
      if (mounted) setState(() => _author = p);
    } catch (_) {
      // 拿不到就退回列表里的昵称，关注按钮按「未关注」起步
    }
  }

  Future<void> _loadRelated() async {
    // 先取同分类；不够再补全站（去重、排除自己），最多 10 篇
    final out = <Article>[];
    void addAll(List<Article> list) {
      for (final a in list) {
        if (a.id == _a.id) continue;
        if (out.any((e) => e.id == a.id)) continue;
        out.add(a);
        if (out.length >= 10) return;
      }
    }

    addAll(await ContentService.fetchArticles(category: _a.category, size: 12));
    if (out.length < 10) {
      addAll(await ContentService.fetchArticles(size: 12));
    }
    if (!mounted) return;
    setState(() => _related = out.take(10).toList());
  }

  Future<void> _toggleLike() async {
    if (_likeBusy) return;
    final sp = Provider.of<SessionProvider>(context, listen: false);
    if (!sp.isLoggedIn) {
      CenterToast.show(context, '请先登录后再点赞', icon: Icons.lock_outline);
      await Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const AuthScreen()));
      return;
    }
    final prevLiked = _liked;
    final prevCount = _likeCount;
    setState(() {
      _likeBusy = true;
      _liked = !prevLiked;
      _likeCount = (_likeCount + (_liked ? 1 : -1)).clamp(0, 1 << 30);
    });
    try {
      final r = await ContentService.toggleArticleLike(_a.id);
      if (!mounted) return;
      setState(() {
        _liked = r.liked;
        _likeCount = r.likeCount;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _liked = prevLiked;
        _likeCount = prevCount;
      });
      CenterToast.show(
        context,
        e
            .toString()
            .replaceFirst(RegExp(r'^(ApiException|Exception):\s*'), ''),
      );
    } finally {
      if (mounted) setState(() => _likeBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final paras = _a.paragraphs;
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(title: const Text('文章详情')),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          if (_a.isPending || _a.isRejected) _statusBanner(),

          // ── 标题 ──
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
            child: Text(
              _a.title,
              style: const TextStyle(
                  fontSize: 21,
                  height: 1.35,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary),
            ),
          ),
          const SizedBox(height: 14),

          // ── 作者行：头像 + 名字 + 城市 / 右侧关注 ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              children: [
                GestureDetector(
                  onTap: _openAuthor,
                  child: UserAvatar(
                    url: ApiConfig.mediaUrl(_author?.avatar),
                    userId: _a.authorId,
                    radius: 18,
                    vipLevel: _author?.vip.level ?? 0,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GestureDetector(
                    onTap: _openAuthor,
                    behavior: HitTestBehavior.opaque,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _a.authorName.isEmpty ? '钓友' : _a.authorName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textPrimary),
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            const Icon(Icons.place_outlined,
                                size: 12, color: AppTheme.textSecondary),
                            const SizedBox(width: 2),
                            Flexible(
                              child: Text(
                                _a.city.isNotEmpty ? _a.city : _a.categoryLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 11.5,
                                    color: AppTheme.textSecondary),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                if (_showFollow) ...[
                  const SizedBox(width: 8),
                  FollowButton(
                    // 作者资料回来后 initialFollowing 才有值，
                    // key 一变就重建，否则按钮会一直停在「未关注」
                    key: ValueKey('art-follow-${_author?.isFollowing}'),
                    userId: _a.authorId,
                    initialFollowing: _author?.isFollowing ?? false,
                    compact: true,
                  ),
                ],
              ],
            ),
          ),

          // ── 日期 ──
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
            child: Text(
              [
                _a.dateText,
                '${_a.views} 次浏览',
                if (_likeCount > 0) '$_likeCount 人点赞',
              ].where((e) => e.isNotEmpty).join(' · '),
              style:
                  const TextStyle(fontSize: 11.5, color: AppTheme.textSecondary),
            ),
          ),
          const Divider(height: 1, color: AppTheme.divider),

          // ── 封面 ──
          if (_a.cover.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: CachedNetworkImage(
                  imageUrl: _a.cover,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => const ColoredBox(
                    color: AppTheme.primarySoft,
                    child: AspectRatio(aspectRatio: 16 / 10),
                  ),
                  errorWidget: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            ),

          // ── 正文 ──
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
            child: _loading
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 30),
                    child: Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                : paras.isEmpty
                    ? const Text('这篇还没有正文',
                        style: TextStyle(
                            fontSize: 13, color: AppTheme.textSecondary))
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: paras
                            .map((p) => Padding(
                                  padding: const EdgeInsets.only(bottom: 14),
                                  child: Text(p,
                                      style: const TextStyle(
                                          fontSize: 15,
                                          height: 1.75,
                                          color: AppTheme.textPrimary)),
                                ))
                            .toList(),
                      ),
          ),

          // ── 点赞 ──
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 20),
            child: Center(child: _likeButton()),
          ),

          const Divider(height: 1, color: AppTheme.divider),
          const SizedBox(height: 14),

          // ── 广告位 ──
          const AdSlot(),
          const SizedBox(height: 18),

          // ── 相关阅读（10 篇） ──
          if (_related.isNotEmpty) ...[
            const Divider(height: 1, color: AppTheme.divider),
            const Padding(
              padding: EdgeInsets.fromLTRB(18, 16, 18, 8),
              child: Row(
                children: [
                  Text('相关阅读',
                      style: TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textPrimary)),
                  SizedBox(width: 6),
                  Text('MORE',
                      style: TextStyle(
                          fontSize: 10,
                          letterSpacing: .8,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textSecondary)),
                ],
              ),
            ),
            for (final a in _related) _relatedTile(a),
          ],

          const SizedBox(height: 12),
          const Divider(height: 1, color: AppTheme.divider),
          const SizedBox(height: 14),

          // ── 我也要投稿 ──
          Center(
            child: TextButton.icon(
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                final navigator = Navigator.of(context);
                final ok = await navigator.push<bool>(
                  MaterialPageRoute(
                      builder: (_) => PublishArticleScreen(
                          defaultCategory: _a.category)),
                );
                if (ok == true) {
                  messenger.showSnackBar(
                    const SnackBar(content: Text('已提交，审核通过后会显示在列表里')),
                  );
                }
              },
              icon: const Icon(Icons.edit_outlined, size: 17),
              label: const Text('我也要投稿', style: TextStyle(fontSize: 13.5)),
            ),
          ),
          const SizedBox(height: 28),
        ],
      ),
    );
  }

  /// 是不是该显示关注按钮：有作者 id、不是自己
  bool get _showFollow {
    if (_a.authorId.trim().isEmpty) return false;
    if (_author?.isMe == true) return false;
    return true;
  }

  void _openAuthor() {
    final id = _a.authorId.trim();
    if (id.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => UserProfileScreen(userId: id)),
    );
  }

  /// 点赞按钮：数字大于文案（用户要求「数字显示大于后面的单位」同理）
  Widget _likeButton() {
    final active = _liked;
    final fg = active ? Colors.white : AppTheme.textPrimary;
    return GestureDetector(
      onTap: _likeBusy ? null : _toggleLike,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
        decoration: BoxDecoration(
          color: active ? AppTheme.primary : AppTheme.surface,
          borderRadius: BorderRadius.circular(AppTheme.radiusPill),
          border: Border.all(
            color: active ? AppTheme.primary : AppTheme.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(active ? Icons.thumb_up_alt : Icons.thumb_up_alt_outlined,
                size: 17, color: fg),
            const SizedBox(width: 6),
            if (_likeCount > 0) ...[
              Text('$_likeCount',
                  style: TextStyle(
                      fontSize: 16,
                      height: 1.1,
                      fontWeight: FontWeight.w800,
                      color: fg)),
              const SizedBox(width: 3),
              Text('人觉得有用',
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: fg)),
            ] else
              Text(active ? '已点赞' : '点个赞',
                  style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: fg)),
          ],
        ),
      ),
    );
  }

  /// 相关阅读的一行：标题 + 日期/浏览，右边小封面
  Widget _relatedTile(Article a) {
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ArticleDetailScreen(article: a)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    a.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14,
                        height: 1.45,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    [
                      a.categoryLabel,
                      a.dateText,
                      '${a.views} 次浏览',
                    ].where((e) => e.isNotEmpty).join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 11, color: AppTheme.textSecondary),
                  ),
                ],
              ),
            ),
            if (a.cover.isNotEmpty) ...[
              const SizedBox(width: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CachedNetworkImage(
                  imageUrl: a.cover,
                  width: 76,
                  height: 58,
                  fit: BoxFit.cover,
                  placeholder: (_, __) =>
                      const ColoredBox(color: AppTheme.primarySoft),
                  errorWidget: (_, __, ___) =>
                      const ColoredBox(color: AppTheme.primarySoft),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 自己投稿时的审核状态提示
  Widget _statusBanner() {
    final rejected = _a.isRejected;
    final color = rejected ? AppTheme.danger : AppTheme.warning;
    final bg = rejected ? AppTheme.dangerLight : AppTheme.warningLight;
    final text = rejected
        ? '这篇没有通过审核${_a.rejectReason.isNotEmpty ? "：${_a.rejectReason}" : ""}'
        : '这篇还在审核中，通过后才会出现在列表里';
    return Container(
      margin: const EdgeInsets.fromLTRB(18, 14, 18, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(rejected ? Icons.error_outline : Icons.schedule,
              size: 15, color: color),
          const SizedBox(width: 7),
          Expanded(
            child: Text(text,
                style: TextStyle(fontSize: 12, color: color, height: 1.4)),
          ),
        ],
      ),
    );
  }
}
