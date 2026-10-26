import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models/post.dart';
import '../services/api_config.dart';
import 'user_avatar.dart';

/// 双列瀑布流里的一张「渔获卡」
///
/// ★ 版式照用户给的参考图（钓友圈）一比一还原：
///   图片区  · 左上 黑底胶囊里叠 3 张小鱼图 + 条数
///           · 右上 黑底胶囊 + 评论数
///           · 底部 渐变压暗：鱼种名（+N 种）/ 钓法·重量 / 右下「指数」亮绿胶囊
///   文字区  · 正文两行 → 城市 → 头像 / 昵称 / LV / 点赞
/// 颜色**不照抄参考图的荧光黄绿**：整体走 App 现成的绿色系
/// （指数胶囊用 `0xFFB6F09A` + 深绿字，选中态用近黑 `0xFF15181A`）。
class WaterfallPostCard extends StatelessWidget {
  final Post post;
  final VoidCallback onTap;

  const WaterfallPostCard({super.key, required this.post, required this.onTap});

  // ───────────────────────── 数据推导 ─────────────────────────

  List<String> get _fishNames => post.fish
      .map((e) => (e['name'] ?? '').toString().trim())
      .where((n) => n.isNotEmpty)
      .toList();

  /// 鱼种标题：前两种 + 「+N 种」
  String get _fishTitle {
    final names = _fishNames;
    if (names.isEmpty) {
      return post.category == 'post' ? '今日鱼获' : post.categoryLabel;
    }
    final head = names.take(2).join(' ');
    return names.length > 2 ? '$head +${names.length - 2} 种' : head;
  }

  /// 前两种鱼名（加粗那部分）与「+N 种」后缀分开，参考图里两者字重不同
  String get _fishHead {
    final names = _fishNames;
    if (names.isEmpty) return _fishTitle;
    return names.take(2).join(' ');
  }

  String get _fishSuffix {
    final n = _fishNames.length;
    return n > 2 ? ' +${n - 2} 种' : '';
  }

  /// 鱼获总条数（左上角标）
  int get _fishCount {
    var n = 0;
    for (final e in post.fish) {
      n += int.tryParse('${e['count'] ?? 1}') ?? 1;
    }
    return n <= 0 ? 1 : n;
  }

  /// 副标题：分类 · 条数（后端没有「钓法/重量」字段，用现有数据拼）
  String get _meta {
    final n = _fishCount;
    final cat = post.categoryLabel;
    if (post.fish.isEmpty) return cat;
    return '$cat · $n 条';
  }

  /// 热度指数：浏览 + 点赞×4 + 评论×6，压到 55~99
  ///
  /// ★ 系数不能给大：上一版用的 8.5，一条 300 浏览 + 27 赞的普通鱼获算出来
  ///   就是 106 → 被截到 99，等于所有帖子都显示「指数 99」，看着像坏了。
  ///   4.6 的系数下：50 浏览 ≈ 73、300 浏览 ≈ 82、5000 浏览 ≈ 94，才有区分度。
  int get _index {
    final raw = post.viewCount + post.likeCount * 4 + post.commentCount * 6;
    if (raw <= 0) return 60;
    return math.min(99, 55 + (math.log(raw + 1) * 4.6).round());
  }

  String get _cover => post.imageUrls.isNotEmpty ? post.imageUrls.first : '';

  String get _place {
    final c = post.city.trim();
    if (c.isNotEmpty) return c;
    return (post.locationName ?? '').trim();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(.05),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _coverArea()),
            Padding(
              padding: const EdgeInsets.fromLTRB(9, 7, 9, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    (post.body != null && post.body!.trim().isNotEmpty)
                        ? post.body!.trim()
                        : post.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.32,
                      color: Color(0xFF2B2F33),
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (_place.isNotEmpty)
                    Row(
                      children: [
                        const Icon(Icons.place_outlined,
                            size: 11, color: AppTheme.textTertiary),
                        const SizedBox(width: 2),
                        Expanded(
                          child: Text(
                            _place,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 10, color: AppTheme.textTertiary),
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 5),
                  _footer(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _footer() {
    return Row(
      children: [
        UserAvatar(
          url: post.avatarUrl,
          userId: post.userId,
          radius: 9,
          vipLevel: post.authorVip,
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            post.username ?? '钓友',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFF4A5056)),
          ),
        ),
        const SizedBox(width: 3),
        // LV 角标：参考图是纯黑小胶囊 + 白字
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: .5),
          decoration: BoxDecoration(
            color: const Color(0xFF15181A),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            'LV${post.userLevel <= 0 ? 1 : post.userLevel}',
            style: const TextStyle(
                fontSize: 8,
                height: 1.3,
                fontWeight: FontWeight.w700,
                color: Colors.white),
          ),
        ),
        const Spacer(),
        Icon(
          post.likedByMe ? Icons.thumb_up : Icons.thumb_up_outlined,
          size: 11,
          color: post.likedByMe ? AppTheme.primary : AppTheme.textTertiary,
        ),
        const SizedBox(width: 2),
        Text('${post.likeCount}',
            style: const TextStyle(fontSize: 10, color: AppTheme.textTertiary)),
      ],
    );
  }

  /// 图片区
  Widget _coverArea() {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (_cover.isEmpty)
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF23543F), Color(0xFF10251C)],
              ),
            ),
            alignment: Alignment.center,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                _fishTitle,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 15,
                    fontWeight: FontWeight.w700),
              ),
            ),
          )
        else
          CachedNetworkImage(
            imageUrl: ApiConfig.mediaUrl(_cover) ?? '',
            fit: BoxFit.cover,
            placeholder: (_, __) => Container(color: const Color(0xFFE7EBE9)),
            errorWidget: (_, __, ___) =>
                Container(color: const Color(0xFFE7EBE9)),
          ),

        // 底部渐变（压在鱼种名下面）
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 96,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black.withOpacity(.72)],
                ),
              ),
            ),
          ),
        ),

        // 右上：评论数
        Positioned(
          right: 6,
          top: 6,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(.5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.mode_comment_outlined,
                    size: 10, color: Colors.white),
                const SizedBox(width: 3),
                Text('${post.commentCount}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),

        // 底部文字：鱼种名 / 分类·条数 / 指数
        Positioned(
          left: 8,
          right: 8,
          bottom: 8,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: _fishHead),
                          if (_fishSuffix.isNotEmpty)
                            TextSpan(
                              text: _fishSuffix,
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFFCFD8D2),
                              ),
                            ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        height: 1.15,
                        fontWeight: FontWeight.w800,
                        shadows: [
                          Shadow(color: Colors.black38, blurRadius: 4),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  // 指数胶囊：亮绿底 + 深绿字（参考图那颗荧光胶囊的「本 App 配色版」）
                  Container(
                    padding: const EdgeInsets.fromLTRB(6, 2, 7, 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFB6F09A),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          '指数',
                          style: TextStyle(
                              fontSize: 8.5,
                              height: 1.2,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1E4A24)),
                        ),
                        const SizedBox(width: 3),
                        Text(
                          '$_index',
                          style: const TextStyle(
                              fontSize: 12,
                              height: 1.1,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF14381A)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                _meta,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFFDDE4DF),
                  fontSize: 10.5,
                  height: 1.2,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

}

/// 双列瀑布流容器
///
/// 两张卡高度恒定（图片区按剩余高度撑开），所以直接用 GridView 的固定
/// childAspectRatio 就够；首页把它塞进 ListView 时传 `shrinkWrap: true`。
class WaterfallGrid extends StatelessWidget {
  final List<Post> posts;
  final void Function(Post) onTap;
  final EdgeInsets padding;
  final bool shrinkWrap;
  final ScrollPhysics? physics;
  final double childAspectRatio;

  const WaterfallGrid({
    super.key,
    required this.posts,
    required this.onTap,
    this.padding = const EdgeInsets.fromLTRB(12, 8, 12, 12),
    this.shrinkWrap = false,
    this.physics,
    // .52 ≈ 卡宽 200 时总高 385：图片 4:3 + 两行字 + 城市 + 底部行
    this.childAspectRatio = .52,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: padding,
      shrinkWrap: shrinkWrap,
      physics: physics ?? (shrinkWrap ? const NeverScrollableScrollPhysics() : null),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: childAspectRatio,
      ),
      itemCount: posts.length,
      itemBuilder: (_, i) => WaterfallPostCard(
        post: posts[i],
        onTap: () => onTap(posts[i]),
      ),
    );
  }
}
