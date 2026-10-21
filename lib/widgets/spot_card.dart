import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models/fishing_spot.dart';
import '../utils/coord_transform.dart';

/// 钓点信息小卡片（首页「附近钓点」横向列表）
///
/// 布局（固定宽高，禁止内容把卡片撑变形）：
///   左：80×80 方形缩略图（原图 cover 裁切，尺寸不随原图比例变化）
///   右：第 1 行 名称 + 评分
///       第 2 行 类型标签 + 距离
///       第 3 行 标签 chips（最多 2 个，超出省略号，不换行不溢出）
/// [distanceMeters] 传入时显示「1.2km」这类距我距离（按用户定位实时计算）。
class SpotCard extends StatelessWidget {
  final FishingSpot spot;
  final VoidCallback? onTap;

  /// 距当前定位的直线距离（米）；null 表示未定位成功，不显示
  final double? distanceMeters;

  const SpotCard({
    super.key,
    required this.spot,
    this.onTap,
    this.distanceMeters,
  });

  static const double cardWidth = 214;
  static const double cardHeight = 96;
  static const double _thumb = 78;

  /// 标签列表（后台 tags 用逗号分隔，最多展示 2 个 —— 卡片窄，多了必挤）
  List<String> get _tags {
    final raw = spot.tags.trim();
    if (raw.isEmpty) return const [];
    return raw
        .split(RegExp(r'[,，、\s]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .take(2)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      child: Container(
        width: cardWidth,
        height: cardHeight,
        margin: const EdgeInsets.only(right: 10),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          border: Border.all(color: AppTheme.divider),
          boxShadow: AppTheme.lightShadow,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 缩略图：固定方框，原图等比裁切填满
            SizedBox(
              width: _thumb,
              height: _thumb,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: spot.coverUrl != null
                    ? CachedNetworkImage(
                        imageUrl: spot.coverUrl!,
                        fit: BoxFit.cover,
                        width: _thumb,
                        height: _thumb,
                        placeholder: (_, __) =>
                            Container(color: AppTheme.primarySoft),
                        errorWidget: (_, __, ___) => _placeholder(),
                      )
                    : _placeholder(),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // ① 名称 + 评分
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          spot.name,
                          style: const TextStyle(
                              fontSize: 13.5, fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.star_rounded,
                          size: 12.5, color: AppTheme.star),
                      const SizedBox(width: 1),
                      Text(
                        spot.rating.toStringAsFixed(1),
                        style: const TextStyle(
                            fontSize: 11, color: AppTheme.textSecondary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  // ② 类型标签 + 距离
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryLight,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          spot.type,
                          style: const TextStyle(
                              fontSize: 10, color: AppTheme.primary),
                          maxLines: 1,
                        ),
                      ),
                      if (distanceMeters != null) ...[
                        const SizedBox(width: 5),
                        const Icon(Icons.near_me,
                            size: 10.5, color: AppTheme.textSecondary),
                        const SizedBox(width: 1.5),
                        Flexible(
                          child: Text(
                            CoordTransform.formatDistance(distanceMeters!),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 10.5,
                                color: AppTheme.textSecondary,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (_tags.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    // ③ 标签 chips：单行、可压缩、不换行
                    Row(
                      children: [
                        for (var i = 0; i < _tags.length; i++) ...[
                          if (i > 0) const SizedBox(width: 4),
                          Flexible(child: _tagChip(_tags[i])),
                        ],
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tagChip(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: AppTheme.primarySoft,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: AppTheme.primaryBorder),
        ),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 9.5,
            height: 1.35,
            color: AppTheme.primaryDark,
          ),
        ),
      );

  Widget _placeholder() => Container(
        decoration: const BoxDecoration(gradient: AppTheme.brandGradient),
        child: const Center(
          child: Icon(Icons.place, color: Colors.white, size: 24),
        ),
      );
}
