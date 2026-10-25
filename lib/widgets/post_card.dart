import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../models/post.dart';
import '../services/api_config.dart';
import '../services/post_service.dart';
import '../services/session_provider.dart';
import '../screens/post_detail_screen.dart';
import '../screens/user_profile_screen.dart';
import '../widgets/fish_art.dart';
import '../widgets/follow_button.dart';
import '../widgets/post_video_player.dart';
import '../widgets/user_avatar.dart';
import 'center_toast.dart';

/// 信息流卡片（图一样式）
///
/// 布局顺序：作者行（头像 / 昵称 / 等级标签 / 关注按钮）→ 标题正文 →
/// 图片拼贴（1 大 2 小 / 九宫格）→ 信息卡（渔获 / 价格）→ 数据行（浏览 / 评论 / 点赞 / 时间）。
///
/// 和旧版的差别：旧版是「缩略图 + 标题 + 定位」那种列表感很重的样式，
/// 图片只有 88px 见方，正文最多两行。现在改成大图主导的九宫格拼贴，
/// 正文放到 6 行，作者行给一个大号描边关注按钮——这才是「刷动态」的节奏。
class PostCard extends StatefulWidget {
  final Post post;

  /// 作者操作：当传入且当前帖子是本人发布时，卡片右上角显示编辑 / 删除按钮
  final void Function(Post)? onEdit;
  final void Function(Post)? onDelete;

  const PostCard({
    super.key,
    required this.post,
    this.onEdit,
    this.onDelete,
  });

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  late Post _post;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _post = widget.post;
    // 单图且比例未知时，先探一次真实尺寸，避免先按 4:3 排出错的高度再跳变
    final imgs = _post.imageUrls;
    if (!_post.isVideo && imgs.length == 1 && !_aspectCache.containsKey(imgs.first)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _rememberAspect(imgs.first);
      });
    }
  }

  Future<void> _onLike() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final nowLiked = await PostService.toggleLike(_post.id, _post.likedByMe);
      setState(() {
        _post = _post.copyWith(
          likedByMe: nowLiked,
          likeCount: _post.likeCount + (nowLiked ? 1 : -1),
        );
      });
    } catch (e) {
      if (!mounted) return;
      CenterToast.show(context,
          e is Exception ? e.toString().replaceFirst('Exception: ', '') : '操作失败，请稍后再试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openAuthor() {
    if (_post.userId.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => UserProfileScreen(userId: _post.userId),
      ),
    );
  }

  /// 进入动态详情（点正文 / 图片 / 评论数都走这里）
  void _openDetail() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PostDetailScreen(post: _post)),
    );
  }

  static Color _categoryColor(String category) =>
      AppTheme.categoryColor(category);

  /// 缓存每张图解码后的宽高比
  static final Map<String, double> _aspectCache = {};

  /// 未知比例时的兜底值（4:3，接近常见手机拍摄横图）
  static const double _defaultAspect = 4 / 3;

  bool _aspectResolved = false;

  double _aspectOf(String url) => _aspectCache[url] ?? _defaultAspect;

  void _rememberAspect(String url) {
    _resolveAspect(url, CachedNetworkImageProvider(url));
  }

  void _resolveAspect(String url, ImageProvider provider) {
    final stream = provider.resolve(const ImageConfiguration());
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        final w = info.image.width.toDouble();
        final h = info.image.height.toDouble();
        if (w > 0 && h > 0) {
          final ratio = (w / h).clamp(0.5, 3.0);
          final was = _aspectCache[url];
          _aspectCache[url] = ratio;
          final changed = was == null || (was - ratio).abs() > 0.01;
          if (changed && !_aspectResolved && mounted) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _aspectResolved = true);
            });
          }
        }
        stream.removeListener(listener);
      },
      onError: (_, __) => stream.removeListener(listener),
    );
    stream.addListener(listener);
  }

  /// 图片占位 / 失败态：加载中显示浅灰骨架，失败显示破图图标
  Widget _image(String url,
      {double? height, double? width, BoxFit fit = BoxFit.cover}) {
    final fixed = height != null;
    return CachedNetworkImage(
      imageUrl: url,
      height: height,
      width: width,
      fit: fit,
      fadeInDuration: const Duration(milliseconds: 180),
      imageBuilder: (ctx, provider) => fixed
          ? SizedBox(
              height: height,
              width: width,
              child: Image(image: provider, fit: fit),
            )
          : Image(image: provider, fit: fit),
      placeholder: (_, __) => Container(
        color: AppTheme.primarySoft,
        alignment: Alignment.center,
        child: const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
              strokeWidth: 1.6, color: AppTheme.primaryBorder),
        ),
      ),
      errorWidget: (_, __, ___) => Container(
        color: AppTheme.primarySoft,
        alignment: Alignment.center,
        child: const Icon(Icons.broken_image_outlined,
            size: 22, color: AppTheme.textSecondary),
      ),
    );
  }

  // ─────────────────────────── 作者行 ───────────────────────────

  /// 图一的作者行：左头像、中间两行（昵称 + 标签），右侧大号描边关注按钮
  Widget _authorRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        GestureDetector(
          onTap: _openAuthor,
          child: UserAvatar(
            url: _post.avatarUrl,
            userId: _post.userId,
            radius: 20,
            vipLevel: _post.authorVip,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: GestureDetector(
            onTap: _openAuthor,
            behavior: HitTestBehavior.opaque,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _post.username ?? '钓友',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    _tag(
                      _post.isCatch ? '今日鱼获' : _post.categoryLabel,
                      bg: AppTheme.categorySoft(_post.category),
                      fg: _categoryColor(_post.category),
                    ),
                    const SizedBox(width: 6),
                    // 深色等级标签：对应图一昵称下的「500 SR」
                    _tag('LV.${_post.userLevel}',
                        bg: const Color(0xFF1E2A24),
                        fg: Colors.white),
                    if (_post.authorVip > 0) ...[
                      const SizedBox(width: 6),
                      _tag('VIP${_post.authorVip}',
                          bg: const Color(0xFF3A2E12),
                          fg: const Color(0xFFF2C14E)),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
        // 作者操作（仅本人 + 调用方给了回调）
        if (_post.isMe && (widget.onEdit != null || widget.onDelete != null)) ...[
          if (widget.onEdit != null)
            InkWell(
              onTap: () => widget.onEdit!(_post),
              borderRadius: BorderRadius.circular(6),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 5, vertical: 4),
                child:
                    Icon(Icons.edit_outlined, size: 18, color: AppTheme.primary),
              ),
            ),
          if (widget.onDelete != null)
            InkWell(
              onTap: () => widget.onDelete!(_post),
              borderRadius: BorderRadius.circular(6),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 5, vertical: 4),
                child: Icon(Icons.delete_outline, size: 19, color: AppTheme.danger),
              ),
            ),
          const SizedBox(width: 4),
        ],
        _followButton(),
      ],
    );
  }

  Widget _tag(String text, {required Color bg, required Color fg}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10.5,
          height: 1.15,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }

  // 作者行右侧的关注按钮（登录且非本人且后端可用时才显示）
  Widget _followButton() {
    if (!ApiConfig.enabled) return const SizedBox.shrink();
    // 注意：这里要 listen:true —— 底部导航是 IndexedStack 保活，
    // 未登录时构建的卡片在登录后不会自动重建，关注按钮会一直不显示
    final myId = Provider.of<SessionProvider>(context).userId;
    if (myId == null || myId == _post.userId || _post.userId.isEmpty) {
      return const SizedBox.shrink();
    }
    return FollowButton(
      userId: _post.userId,
      initialFollowing: _post.isFollowing,
      outline: true,
    );
  }

  // ─────────────────────────── 正文 ───────────────────────────

  Widget _textBlock() {
    final hasTitle = _post.title.trim().isNotEmpty;
    final body = (_post.body ?? '').trim();
    // 标题和正文内容重复时只显示一份（渔获帖标题固定是「今日鱼获分享」）
    final showBody = body.isNotEmpty && body != _post.title.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasTitle)
          Text(
            _post.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 16,
              height: 1.4,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
        if (hasTitle && showBody) const SizedBox(height: 6),
        if (showBody)
          Text(
            body,
            maxLines: 6,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 14.5,
              height: 1.6,
              color: Color(0xFF2B3A33),
            ),
          ),
      ],
    );
  }

  // ─────────────────────────── 图片拼贴 ───────────────────────────

  /// 图一的拼贴：3 张 = 左边一张大图 + 右边两张小图上下叠；2 张 = 左右等分；
  /// 1 张 = 按原比例铺满宽度；≥4 张 = 九宫格（最多 4 格 + 剩余数气泡）
  Widget _collage(List<String> urls) {
    const gap = 4.0;
    // 圆角统一走 ClipRoundedRectangle.radius，测试会拿这个值做护栏
    const radius = BorderRadius.all(Radius.circular(ClipRoundedRectangle.radius));

    if (urls.length == 1) {
      final ratio = _aspectOf(urls.first).clamp(0.66, 1.9);
      final w = MediaQuery.of(context).size.width - 44;
      final h = (w / ratio).clamp(140.0, 300.0);
      return ClipRRect(
        borderRadius: radius,
        child: SizedBox(
          width: double.infinity,
          height: h,
          child: _image(urls.first),
        ),
      );
    }

    if (urls.length == 2) {
      return SizedBox(
        height: 150,
        child: Row(
          children: [
            Expanded(
                child: ClipRRect(
                    borderRadius: radius, child: _image(urls[0]))),
            const SizedBox(width: gap),
            Expanded(
                child: ClipRRect(
                    borderRadius: radius, child: _image(urls[1]))),
          ],
        ),
      );
    }

    if (urls.length >= 4) {
      // 九宫格：两行两列 + 右下角剩余数
      final extra = urls.length - 4;
      return SizedBox(
        height: 190,
        child: Row(
          children: [
            for (var col = 0; col < 2; col++) ...[
              if (col > 0) const SizedBox(width: gap),
              Expanded(
                child: Column(
                  children: [
                    for (var row = 0; row < 2; row++) ...[
                      if (row > 0) const SizedBox(height: gap),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: radius,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              _image(urls[col * 2 + row]),
                              if (col == 1 && row == 1 && extra > 0)
                                Container(
                                  color: Colors.black.withOpacity(0.42),
                                  alignment: Alignment.center,
                                  child: Text(
                                    '+$extra',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 17,
                                        fontWeight: FontWeight.w700),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      );
    }

    // 3 张：左大右两小（图一）
    final extra = urls.length - 3;
    return SizedBox(
      height: 205,
      child: Row(
        children: [
          Expanded(
            flex: 62,
            child: ClipRRect(
              borderRadius: radius,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _image(urls[0]),
                  if (extra > 0)
                    Positioned(
                      right: 6,
                      bottom: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.45),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text('+$extra',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 11)),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: gap),
          Expanded(
            flex: 38,
            child: Column(
              children: [
                Expanded(
                    child: ClipRRect(
                        borderRadius: radius, child: _image(urls[1]))),
                const SizedBox(height: gap),
                Expanded(
                    child: ClipRRect(
                        borderRadius: radius, child: _image(urls[2]))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────── 信息卡 ───────────────────────────

  /// 图一里「分享来自活动」那块：浅灰圆角块 + 左侧小图标 + 两行文字。
  /// 这里承载渔获摘要 / 二手价格 / 钓点位置这三种附带信息。
  Widget? _infoCard() {
    Widget? card;

    if (_post.fish.isNotEmpty) {
      final names = _post.fish
          .map((f) {
            final n = (f['name'] ?? '').toString();
            final c = (f['count'] as num?)?.toInt() ?? 1;
            return c > 1 ? '$n ×$c' : n;
          })
          .where((s) => s.isNotEmpty)
          .take(3)
          .join(' · ');
      final first = (_post.fish.first['name'] ?? '鲫鱼').toString();
      card = _infoTile(
        leading: SizedBox(
          width: 38,
          height: 38,
          child: Center(
            child: FishArt(name: first, size: 34, rarity: 'common'),
          ),
        ),
        title: '本次渔获',
        subtitle: names.isEmpty ? '已记录鱼种' : names,
      );
    } else if (_post.isTrade && _post.price.isNotEmpty) {
      card = _infoTile(
        leading: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: AppTheme.dangerLight,
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: const Icon(Icons.sell_outlined,
              size: 19, color: AppTheme.danger),
        ),
        title: _post.category == 'sell' ? '出售价格' : '求购预算',
        subtitle: '¥${_post.price}',
        subtitleColor: AppTheme.danger,
      );
    } else if (_post.locationName != null &&
        _post.locationName!.trim().isNotEmpty) {
      card = _infoTile(
        leading: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: AppTheme.primaryLight,
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: const Icon(Icons.place_outlined,
              size: 19, color: AppTheme.primary),
        ),
        title: '钓点位置',
        subtitle: _post.locationName!.trim(),
      );
    } else if (!_post.locPublic && _post.category == 'post') {
      card = _infoTile(
        leading: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: AppTheme.primarySoft,
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: const Icon(Icons.location_off_outlined,
              size: 19, color: AppTheme.textSecondary),
        ),
        title: '钓点位置',
        subtitle: '作者已隐藏钓点',
      );
    }

    return card;
  }

  Widget _infoTile({
    required Widget leading,
    required String title,
    required String subtitle,
    Color? subtitleColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F7F6),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        children: [
          ClipRRect(borderRadius: BorderRadius.circular(8), child: leading),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.2,
                    color: subtitleColor ?? AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right,
              size: 17, color: AppTheme.textSecondary),
        ],
      ),
    );
  }

  // ─────────────────────────── 数据行 ───────────────────────────

  Widget _actionsRow() {
    final muted = Colors.grey.shade600;
    return Row(
      children: [
        _metric(Icons.visibility_outlined, _fmtCount(_post.viewCount), muted),
        const SizedBox(width: 18),
        GestureDetector(
          onTap: _openDetail,
          behavior: HitTestBehavior.opaque,
          child: _metric(
              Icons.chat_bubble_outline, _fmtCount(_post.commentCount), muted),
        ),
        const SizedBox(width: 18),
        GestureDetector(
          onTap: _onLike,
          behavior: HitTestBehavior.opaque,
          child: _metric(
            _post.likedByMe ? Icons.favorite : Icons.favorite_border,
            _fmtCount(_post.likeCount),
            _post.likedByMe ? AppTheme.danger : muted,
          ),
        ),
        const Spacer(),
        Text(
          _post.timeAgo,
          style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
        ),
      ],
    );
  }

  /// 大数字压缩：9021 → 9021，12345 → 1.2万（信息流里不占宽度）
  String _fmtCount(int n) {
    if (n < 10000) return '$n';
    final w = n / 10000;
    return w >= 10 ? '${w.round()}万' : '${w.toStringAsFixed(1)}万';
  }

  Widget _metric(IconData icon, String text, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 17, color: color),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(fontSize: 12.5, color: color)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasMedia =
        _post.isVideo || _post.imageUrls.isNotEmpty;
    // 只构建一次信息卡：它内部可能包含 FishArt 绘制，重复构建是白白的开销
    final info = _infoCard();
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 8),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _openDetail,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _authorRow(),
                const SizedBox(height: 9),
                _textBlock(),
                if (hasMedia) ...[
                  const SizedBox(height: 9),
                  if (_post.isVideo)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: PostVideoPlayer(url: _post.videoUrl!, height: 232),
                    )
                  else
                    _collage(_post.imageUrls),
                ],
                if (info != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 9),
                    child: info,
                  ),
                const SizedBox(height: 10),
                _actionsRow(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 圆角裁剪小工具（保留给旧调用方，新代码直接用 ClipRRect）
class ClipRoundedRectangle extends StatelessWidget {
  /// 信息流图片的统一圆角：8 是「有圆角但不显得药丸」的临界值
  static const double radius = 8;

  final Widget child;
  const ClipRoundedRectangle({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(borderRadius: BorderRadius.circular(radius), child: child);
  }
}
