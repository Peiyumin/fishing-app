import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models/fishing_spot.dart';
import '../utils/coord_transform.dart';

/// 钓点信息小卡片（首页「附近钓点」横向列表）
///
/// 布局：左侧固定 68×68 方形缩略图（原图 BoxFit.cover 等比裁切，尺寸不随原图比例变化）
///     右侧：名称 → 「类型 + 距离 + 评分」→ 标签
/// [distanceMeters] 传入时会显示「1.2km」这类距我距离（按用户定位实时计算）。
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

  static const double _thumb = 68;

  /// 标签列表（后台 tags 用逗号分隔，最多展示 3 个）
  List<String> get _tags {
    final raw = spot.tags.trim();
    if (raw.isEmpty) return const [];
    return raw
        .split(RegExp(r'[,，、\s]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .take(3)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      child: Container(
        width: 214,
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
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    spot.name,
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryLight,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(spot.type,
                            style: const TextStyle(
                                fontSize: 10.5, color: AppTheme.primary)),
                      ),
                      const SizedBox(width: 5),
                      if (distanceMeters != null) ...[
                        const Icon(Icons.near_me,
                            size: 11, color: AppTheme.textSecondary),
                        const SizedBox(width: 2),
                        Text(
                          CoordTransform.formatDistance(distanceMeters!),
                          style: const TextStyle(
                              fontSize: 11,
                              color: AppTheme.textSecondary,
                              fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(width: 5),
                      ],
                      const Spacer(),
                      const Icon(Icons.star, size: 13, color: AppTheme.star),
                      const SizedBox(width: 2),
                      Text(spot.rating.toString(),
                          style: const TextStyle(fontSize: 11.5)),
                    ],
                  ),
                  if (_tags.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    SizedBox(
                      height: 17,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _tags.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 4),
                        itemBuilder: (_, i) => Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppTheme.primarySoft,
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(color: AppTheme.primaryBorder),
                          ),
                          child: Center(
                            child: Text(
                              _tags[i],
                              style: const TextStyle(
                                  fontSize: 10,
                                  color: AppTheme.primaryDark),
                            ),
                          ),
                        ),
                      ),
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

  Widget _placeholder() => Container(
        decoration: const BoxDecoration(gradient: AppTheme.brandGradient),
        child: const Center(
          child: Icon(Icons.place, color: Colors.white, size: 24),
        ),
      );
}
