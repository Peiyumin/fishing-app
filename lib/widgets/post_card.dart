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
import '../widgets/location_label.dart';
import '../widgets/post_video_player.dart';
import '../widgets/user_avatar.dart';
import 'center_toast.dart';

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

  /// 图片区排版（信息流里用缩略图，不占上下空间）：
  /// 1 张 → 单张缩略图（高 112，宽按原比例，最宽 60%）
  /// 2 张及以上 → 一行最多三张方形小图，第 3 张叠 "+N"
  /// 详情页才展示大图
  Widget _buildImageGrid(List<String> urls) {
    final width = MediaQuery.of(context).size.width - 48; // 卡片外边距+内边距
    if (urls.length == 1) {
      final ratio = _aspectOf(urls.first).clamp(0.6, 2.0);
      const h = 112.0;
      final w = (h * ratio).clamp(96.0, width * 0.62);
      return ClipRoundedRectangle(
        child: Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: w,
            height: h,
            child: _image(urls.first, width: w, height: h, fit: BoxFit.cover),
          ),
        ),
      );
    }
    final showCount = urls.length >= 3 ? 3 : 2;
    const gap = 6.0;
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

  /// 渔获固定标题：左侧鱼形标记 + 「今日鱼获分享」+ 渐变下划线
  Widget _catchTitle() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                gradient: AppTheme.brandGradient,
                borderRadius: BorderRadius.circular(7),
              ),
              child: const Icon(Icons.set_meal, size: 14, color: Colors.white),
            ),
            const SizedBox(width: 7),
            const Text(
              '今日鱼获分享',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                height: 1.2,
                letterSpacing: 0.3,
                color: AppTheme.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        // 标题下面的小渐变条：让标题有「设计感」，不是一行干巴巴的字
        Container(
          width: 44,
          height: 3,
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [
              AppTheme.primary,
              AppTheme.accent,
            ]),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ],
    );
  }

  /// 渔获摘要：浅绿底 + 鱼种条数，一行放不下自动换行
  Widget _catchSummaryLine() {
    final summary = _post.catchSummary;
    if (summary.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: AppTheme.primaryLight,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Icon(Icons.phishing, size: 13, color: AppTheme.primary),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              summary,
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.3,
                fontWeight: FontWeight.w600,
                color: AppTheme.primaryDark,
              ),
            ),
          ),
        ],
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
        // 卡片整块可点：标题 / 正文 / 图片任意位置都进详情
        onTap: _openDetail,
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
                    child: UserAvatar(
                      url: _post.avatarUrl,
                      userId: _post.userId,
                      radius: 16,
                      vipLevel: _post.authorVip,
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
              // 标题：渔获统一「今日鱼获分享」，其它类别显示原标题 + 类别标签
              if (_post.isCatch)
                _catchTitle()
              else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
                    Expanded(
                      child: Text(_post.displayTitle,
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
              // 渔获内容：鱼种 + 条数（「鲫鱼 2 条 · 鲤鱼 1 条」）
              if (_post.fish.isNotEmpty) ...[
                const SizedBox(height: 8),
                _catchSummaryLine(),
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
                            child: LocationLabel(
                              raw: _post.locationName!,
                              style: const TextStyle(
                                  fontSize: 13, color: AppTheme.textSecondary),
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (!_post.locPublic && _post.category == 'post')
                    const Expanded(
                      child: Row(
                        children: [
                          Icon(Icons.location_off,
                              size: 15, color: AppTheme.textSecondary),
                          SizedBox(width: 3),
                          Text('钓点已隐藏',
                              style: TextStyle(
                                  fontSize: 12.5,
                                  color: AppTheme.textSecondary)),
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
  final Widget child;
  const ClipRoundedRectangle({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(borderRadius: BorderRadius.circular(10), child: child);
  }
}
