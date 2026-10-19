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
import '../widgets/follow_button.dart';
import '../widgets/post_video_player.dart';

/// 首页/发现页的信息流卡片
/// 模板：标题 + 图片 +（定位 / 评论 / 点赞）
class PostCard extends StatefulWidget {
  final Post post;

  const PostCard({super.key, required this.post});

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
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
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

  /// 图片区九宫格排版：
  /// 1 张 → 大图；2 张 → 一行两图；3 张及以上 → 一行三图，
  /// 超过 3 张时第 3 张叠 "+N" 角标（点击进详情看全部）
  Widget _buildImageGrid(List<String> urls) {
    final width = MediaQuery.of(context).size.width - 48; // 卡片外边距+内边距
    if (urls.length == 1) {
      // 单图：按图片真实比例展示（竖图/长图不再被固定高度裁成一条）
      // 用 LayoutBuilder 拿到精确可用宽度，避免 Image 按原始像素宽排版导致
      // 图只占卡片一部分；高度 = 宽度 / 比例，上限 420
      return ClipRoundedRectangle(
        child: LayoutBuilder(
          builder: (ctx, cons) {
            final w = cons.maxWidth.isFinite ? cons.maxWidth : width;
            final ratio = _aspectOf(urls.first);
            final h = (w / ratio).clamp(120.0, 420.0);
            return SizedBox(
              width: w,
              height: h,
              child: _image(urls.first, width: w, height: h, fit: BoxFit.cover),
            );
          },
        ),
      );
    }
    final showCount = urls.length >= 3 ? 3 : 2;
    const gap = 6.0;
    final cell = (width - gap * (showCount - 1)) / showCount;
    final height = urls.length == 2 ? cell * 0.72 : cell;
    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: List.generate(showCount, (i) {
          final extra = urls.length - showCount; // 未被展示的剩余张数
          // 用 Expanded 均分宽度，避免 Stack 在无界宽度下约束异常
          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: i == showCount - 1 ? 0 : gap),
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

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => PostDetailScreen(post: _post)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 作者行（点头像/昵称进 TA 的主页）
              Row(
                children: [
                  GestureDetector(
                    onTap: _openAuthor,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: AppTheme.border, width: 1.5),
                      ),
                      child: CircleAvatar(
                        radius: 16,
                        backgroundColor: AppTheme.primarySoft,
                        backgroundImage: _post.avatarUrl != null
                            ? CachedNetworkImageProvider(_post.avatarUrl!)
                            : null,
                        onBackgroundImageError: _post.avatarUrl != null
                            ? (_, __) {}
                            : null,
                        child: _post.avatarUrl == null
                            ? const Icon(Icons.person,
                                size: 18, color: AppTheme.textSecondary)
                            : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: GestureDetector(
                      onTap: _openAuthor,
                      child: Text(
                        _post.username ?? '钓友',
                        style: const TextStyle(fontWeight: FontWeight.w600),
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
              const SizedBox(height: 8),
              // 媒体区：视频动态优先；图片按 1/2/3+ 张分别排版（九宫格样式）
              if (_post.isVideo)
                PostVideoPlayer(url: _post.videoUrl!, height: 240)
              else if (_post.imageUrls.isNotEmpty)
                _buildImageGrid(_post.imageUrls),
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
                  // 评论
                  Row(
                    children: [
                      const Icon(Icons.chat_bubble_outline,
                          size: 16, color: AppTheme.textSecondary),
                      const SizedBox(width: 4),
                      Text('${_post.commentCount}',
                          style: const TextStyle(
                              fontSize: 13, color: AppTheme.textSecondary)),
                    ],
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
  final Widget child;
  const ClipRoundedRectangle({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(borderRadius: BorderRadius.circular(10), child: child);
  }
}
