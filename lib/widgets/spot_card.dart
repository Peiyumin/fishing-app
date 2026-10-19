import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models/fishing_spot.dart';

/// 钓点信息小卡片（首页天气下方展示附近推荐钓点）
/// 横版布局：左侧固定 68×68 方形缩略图 + 右侧名称/类型/评分，
/// 图片一律 BoxFit.cover 裁切，尺寸不随原图比例变化（原图再高也不会撑破卡片）。
class SpotCard extends StatelessWidget {
  final FishingSpot spot;
  final VoidCallback? onTap;
  const SpotCard({super.key, required this.spot, this.onTap});

  static const double _thumb = 68;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      child: Container(
        width: 208,
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
                  SizedBox(
                    height: _thumb - 24,
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: Text(
                        spot.name,
                        style: const TextStyle(
                            fontSize: 13.5, fontWeight: FontWeight.w600),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
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
                      const Spacer(),
                      const Icon(Icons.star, size: 13, color: AppTheme.star),
                      const SizedBox(width: 2),
                      Text(spot.rating.toString(),
                          style: const TextStyle(fontSize: 11.5)),
                    ],
                  ),
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
