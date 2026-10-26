import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../models/badge.dart';
import '../models/post.dart';
import '../services/api_config.dart';
import '../services/badge_hub.dart';
import '../services/post_service.dart';
import '../services/session_provider.dart';
import '../screens/post_detail_screen.dart';
import '../screens/user_profile_screen.dart';
import '../widgets/follow_button.dart';
import '../widgets/post_video_player.dart';
import '../widgets/user_avatar.dart';
import 'center_toast.dart';

/// 首页/发现页的信息流卡片
/// 模板：标题 + 图片 +（定位 / 评论 / 点赞）
class PostCard extends StatefulWidget {
  final Post post;

  /// 「我的动态」页用：长按卡片弹出的编辑 / 删除回调
  final Future<void> Function(Post post)? onEdit;
  final Future<void> Function(Post post)? onDelete;

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
      setState(() => _busy = false);
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

  /// 进入动态详情（点标题 / 正文 / 图片 / 评论数都走这里）
  void _openDetail() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PostDetailScreen(post: _post)),
    );
  }

  /// 类别标识色（统一走设计系统，保证信息流 / 发布中心 / 钓点筛选一致）
  static Color _categoryColor(String category) =>
      AppTheme.categoryColor(category);

  /// 缓存每张图解码后的宽高比
  static final Map<String, double> _aspectCache = {};

  /// 未知比例时的兜底值（4:3，接近常见手机拍摄横图）
  static const double _defaultAspect = 4 / 3;

  /// 当前这张卡片的图比例是否已经拿到；拿到后触发一次重建
  bool _aspectResolved = false;

  double _aspectOf(String url) => _aspectCache[url] ?? _defaultAspect;

  /// 图片解码后记录真实比例；与当前布局用的比例不同则重建一次
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
            // 下一帧再 setState，避免在 build 期间触发重建
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
  /// （之前没有占位，加载失败时是一片纯白，看不出是「正在加载」还是「挂了」）
  Widget _image(String url,
      {double? height, double? width, BoxFit fit = BoxFit.cover}) {
    // 给了明确高度（九宫格/固定尺寸）就铺满；没给高度（单图自适应）就交给
    // 外层 AspectRatio 决定，此时不能再包无约束的 SizedBox，否则图片塌陷
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

  /// 图片区排版：
  /// 1 张 → 单张缩略图（高 112，宽按原比例，最宽 62%，保持原来的样子）
  /// 2 张 → 中间分开，左右各一张、等宽等高
  /// 3 张 → 左边一张大图（占满整高），右边两张小图上下叠
  /// ≥4 张 → 沿用原来的三张方图，第 3 张右上角叠 "+N"
  /// 详情页才展示大图
  Widget _buildImageGrid(List<String> urls) {
    final width = MediaQuery.of(context).size.width - 48; // 卡片外边距+内边距
    const gap = 6.0;

    if (urls.length == 1) {
      final ratio = _aspectOf(urls.first).clamp(0.6, 2.0);
      const h = 112.0;
      final w = (h * ratio).clamp(96.0, width * 0.62);
      // 裁剪框要**贴着图片**（Align 在外、Clip 在内）：
      // 反过来的话 Clip 会撑满整行，图片右侧两个角就不是圆的了（老毛病）
      return Align(
        alignment: Alignment.centerLeft,
        child: ClipRoundedRectangle(
          child: SizedBox(
            width: w,
            height: h,
            child: _image(urls.first, width: w, height: h, fit: BoxFit.cover),
          ),
        ),
      );
    }

    if (urls.length == 2) {
      // 中间分一半，一边一张；高度按卡片宽度定，窄屏不会压成细条
      final h = (width * 0.34).clamp(110.0, 170.0);
      return SizedBox(
        height: h,
        child: Row(
          children: [
            Expanded(
              child: ClipRoundedRectangle(
                child: SizedBox.expand(child: _image(urls[0])),
              ),
            ),
            const SizedBox(width: gap),
            Expanded(
              child: ClipRoundedRectangle(
                child: SizedBox.expand(child: _image(urls[1])),
              ),
            ),
          ],
        ),
      );
    }

    if (urls.length == 3) {
      // 左大右两小：左图更宽更高，右列两张等分高度
      final h = (width * 0.52).clamp(150.0, 240.0);
      return SizedBox(
        height: h,
        child: Row(
          children: [
            Expanded(
              flex: 66,
              child: ClipRoundedRectangle(
                child: SizedBox.expand(child: _image(urls[0])),
              ),
            ),
            const SizedBox(width: gap),
            Expanded(
              flex: 34,
              child: Column(
                children: [
                  Expanded(
                    child: ClipRoundedRectangle(
                      child: SizedBox.expand(child: _image(urls[1])),
                    ),
                  ),
                  const SizedBox(height: gap),
                  Expanded(
                    child: ClipRoundedRectangle(
                      child: SizedBox.expand(child: _image(urls[2])),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final showCount = 3;
    // 缩略图固定 88 见方（原来是按卡片宽度算方图，单张就有 170 多，太占地方）
    const cell = 88.0;
    return SizedBox(
      height: cell,
      child: Row(
        children: List.generate(showCount, (i) {
          final extra = urls.length - showCount; // 未被展示的剩余张数
          return Padding(
            padding: EdgeInsets.only(right: i == showCount - 1 ? 0 : gap),
            child: SizedBox(
              width: cell,
              height: cell,
              child: ClipRoundedRectangle(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _image(urls[i]), // 第 3 张右上角显示剩余数量
                    if (i == 2 && extra > 0)
                      Positioned(
                        right: 4,
                        top: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black54,
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
          );
        }),
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
      tiny: true,
    );
  }

  bool get _hasActions => widget.onEdit != null || widget.onDelete != null;

  /// 长按菜单（只在「我的动态」里传了回调时可用）
  Future<void> _showActions() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.onEdit != null)
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('编辑这条动态'),
                onTap: () => Navigator.pop(ctx, 'edit'),
              ),
            if (widget.onDelete != null)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: AppTheme.danger),
                title: const Text('删除这条动态',
                    style: TextStyle(color: AppTheme.danger)),
                onTap: () => Navigator.pop(ctx, 'del'),
              ),
            ListTile(
              title: const Center(child: Text('取消')),
              onTap: () => Navigator.pop(ctx),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'edit') await widget.onEdit!(_post);
    if (action == 'del') await widget.onDelete!(_post);
  }

  /// 头像后面的徽章（最多 3 枚）
  /// 数据来源：动态里自带就用自带的，否则由 BadgeHub 按作者 id 批量拉
  /// （一屏只发一次请求，见 BadgeHub 注释）。没有徽章时宽度为 0，不占位。
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
          padding: const EdgeInsets.only(left: 4),
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

  /// #RGB / #RRGGBB 都能吃，认不出来返回 null
  Color? _hexColor(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return null;
    if (s.startsWith('#')) s = s.substring(1);
    if (s.length == 3) s = s.split('').map((c) => '$c$c').join();
    if (s.length == 6) {
      final v = int.tryParse(s, radix: 16);
      if (v != null) return Color(0xFF000000 | v);
    }
    if (s.length == 8) {
      final v = int.tryParse(s, radix: 16);
      if (v != null) return Color(v);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      child: InkWell(
        // 卡片整块可点：标题 / 正文 / 图片任意位置都进详情
        onTap: _openDetail,
        // 「我的动态」页长按出编辑 / 删除
        onLongPress: _hasActions ? _showActions : null,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 作者行（点头像/昵称进 TA 的主页）
              // 徽章紧跟在**昵称**后面（按要求不是头像后面），拿到就出现，
              // 没拿到宽度为 0 不占位，老数据 / 后端没升级时版式不受影响。
              Row(
                children: [
                  GestureDetector(
                    onTap: _openAuthor,
                    child: UserAvatar(
                      url: _post.avatarUrl,
                      userId: _post.userId,
                      radius: 16,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: GestureDetector(
                      onTap: _openAuthor,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              _post.username ?? '钓友',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                          _authorBadges(),
                        ],
                      ),
                    ),
                  ),
                  _followButton(),
                  const SizedBox(width: 8),
                  Text(_post.timeAgo,
                      style: const TextStyle(
                          fontSize: 12, color: AppTheme.textSecondary)),
                ],
              ),
              const SizedBox(height: 8),
              // 标题 + 类别标签
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_post.category != 'post') ...[
                    Container(
                      margin: const EdgeInsets.only(top: 2, right: 6),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.categorySoft(_post.category),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(_post.categoryLabel,
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: _categoryColor(_post.category))),
                    ),
                  ],
                  Expanded(
                    child: Text(_post.title,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              if (_post.body != null && _post.body!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(_post.body!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.black87)),
              ],
              // 二手价格（出售=售价 / 求购=预算）
              if (_post.isTrade && _post.price.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppTheme.dangerLight,
                    borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                  ),
                  child: Text(
                    '${_post.category == 'sell' ? '售价' : '预算'} ¥${_post.price}',
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.danger),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              // 媒体区：视频动态优先；图片为缩略图，上下留白避免贴着分割线
              if (_post.isVideo)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: PostVideoPlayer(url: _post.videoUrl!, height: 240),
                )
              else if (_post.imageUrls.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _buildImageGrid(_post.imageUrls),
                ),
              const Divider(height: 1, thickness: 1, color: AppTheme.divider),
              const SizedBox(height: 10),
              // 底部：定位 / 评论 / 点赞
              Row(
                children: [
                  if (_post.locationName != null)
                    Expanded(
                      child: Row(
                        children: [
                          const Icon(Icons.location_on,
                              size: 16, color: AppTheme.textSecondary),
                          Flexible(
                            child: Text(_post.locationName!,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 13, color: AppTheme.textSecondary)),
                          ),
                        ],
                      ),
                    ),
                  const Spacer(),
                  // 评论：整块可点，直接进详情看评论
                  InkWell(
                    onTap: _openDetail,
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 4),
                      child: Row(
                        children: [
                          const Icon(Icons.chat_bubble_outline,
                              size: 16, color: AppTheme.textSecondary),
                          const SizedBox(width: 4),
                          Text('${_post.commentCount}',
                              style: const TextStyle(
                                  fontSize: 13, color: AppTheme.textSecondary)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  // 点赞（可点击切换）
                  InkWell(
                    onTap: _onLike,
                    child: Row(
                      children: [
                        Icon(
                          _post.likedByMe
                              ? Icons.favorite
                              : Icons.favorite_border,
                          size: 16,
                          color: _post.likedByMe ? AppTheme.danger : AppTheme.textSecondary,
                        ),
                        const SizedBox(width: 4),
                        Text('${_post.likeCount}',
                            style: TextStyle(
                                fontSize: 13,
                                color: _post.likedByMe
                                    ? AppTheme.danger
                                    : AppTheme.textSecondary)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 圆角裁剪小工具
class ClipRoundedRectangle extends StatelessWidget {
  /// 圆角固定 8：用户明确说过不要「药丸感」，10 以上就显圆
  static const double radius = 8.0;

  final Widget child;
  const ClipRoundedRectangle({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(borderRadius: BorderRadius.circular(radius), child: child);
  }
}
