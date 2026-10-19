import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models/fishing_spot.dart';

/// 钓点信息小卡片（首页天气下方展示附近推荐钓点）
class SpotCard extends StatelessWidget {
  final FishingSpot spot;
  final VoidCallback? onTap;
  const SpotCard({super.key, required this.spot, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: 200,
        margin: const EdgeInsets.only(right: 10),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            border: Border.all(color: AppTheme.divider),
            boxShadow: AppTheme.lightShadow,
          ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 封面（有图用图，无图用渐变占位）
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(AppTheme.radiusMd)),
              child: spot.coverUrl != null
                  ? CachedNetworkImage(
                      imageUrl: spot.coverUrl!,
                      height: 78,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    )
                  : Container(
                      height: 78,
                      width: double.infinity,
                      decoration: const BoxDecoration(
                        gradient: AppTheme.brandGradient,
                      ),
                      child: const Center(
                        child: Icon(Icons.place, color: Colors.white, size: 28),
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(spot.name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
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
                              fontSize: 11, color: AppTheme.primary)),
                      ),
                      const Spacer(),
                      const Icon(Icons.star,
                          size: 14, color: AppTheme.star),
                      Text(spot.rating.toString(),
                          style: const TextStyle(fontSize: 12)),
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
}
