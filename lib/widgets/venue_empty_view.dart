import 'package:flutter/material.dart';

import '../app_theme.dart';

/// 「本地钓场」空态
///
/// ★ v2.1.92：以前只有一句「暂无相关内容 —— 点右上角「+」提交钓场」，
///   用户分不清是**这一带真没有**、还是**筛选筛空了**、还是**定位没拿到**。
///   现在按用户要求直说「暂无本地钓场数据请联系管理员添加！」，并把
///   自己补数据的入口（提交钓场）一起给出来。
class VenueEmptyView extends StatelessWidget {
  /// 本地范围半径（公里），用于把「查了多大范围」讲清楚
  final int radiusKm;

  /// 是否已经拿到定位：没有定位时要提示先去允许定位，而不是说「附近没有」
  final bool hasPosition;

  /// 提交钓场
  final VoidCallback? onSubmit;

  const VenueEmptyView({
    super.key,
    this.radiusKm = 100,
    this.hasPosition = true,
    this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      // 留成可滚动：外层的下拉刷新照样能用
      padding: const EdgeInsets.fromLTRB(24, 64, 24, 24),
      children: [
        const Icon(Icons.place_outlined, size: 46, color: AppTheme.textTertiary),
        const SizedBox(height: 14),
        const Text(
          '暂无本地钓场数据请联系管理员添加！',
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary),
        ),
        const SizedBox(height: 8),
        Text(
          hasPosition
              ? '已按当前定位查找附近 $radiusKm 公里内的钓场'
              : '未获取到定位，先点上方「按距离排序」允许定位',
          textAlign: TextAlign.center,
          style: const TextStyle(
              fontSize: 12, height: 1.6, color: AppTheme.textSecondary),
        ),
        const SizedBox(height: 18),
        Center(
          child: TextButton.icon(
            onPressed: onSubmit,
            icon: const Icon(Icons.add_location_alt_outlined, size: 18),
            label: const Text('提交我知道的钓场'),
          ),
        ),
      ],
    );
  }
}
