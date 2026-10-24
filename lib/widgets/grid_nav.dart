import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../screens/activity_list_screen.dart';
import '../screens/article_list_screen.dart';
import '../screens/catch_screen.dart';
import '../screens/lure_screen.dart';
import '../screens/mall_screen.dart';
import '../screens/weather_screen.dart';
import '../screens/spots_screen.dart';
import 'center_toast.dart';

/// 首页宫格导航（10 个图标 + 标题）
/// 已实现的频道直接跳页；未实现的用居中提示说明，不用底部 SnackBar
/// （SnackBar 会顶起底部导航和中间的发布按钮）
class GridNav extends StatelessWidget {
  const GridNav({super.key});

  // 10 个频道：图标 + 标题 + 跳转标识
  static const List<_NavItem> _items = [
    _NavItem(Icons.wb_sunny_outlined, '天气', 'weather'),
    _NavItem(Icons.place_outlined, '钓点', 'spot'),
    _NavItem(Icons.catching_pokemon_outlined, '渔获', 'catch'),
    _NavItem(Icons.sports_handball_outlined, '路亚', 'lure'),
    _NavItem(Icons.water_drop_outlined, '黑坑', 'blackpit'),
    _NavItem(Icons.shopping_bag_outlined, '装备', 'gear'),
    _NavItem(Icons.menu_book_outlined, '技巧', 'skill'),
    _NavItem(Icons.event_outlined, '活动', 'event'),
    _NavItem(Icons.storefront_outlined, '商城', 'shop'),
    _NavItem(Icons.live_tv_outlined, '直播', 'live'),
  ];

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
        child: GridView.count(
          crossAxisCount: 5, // 一行 5 个，两行共 10 个
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 0.85,
          children: _items
              .map((it) => _GridCell(
                    item: it,
                    onTap: () => _onTap(context, it),
                  ))
              .toList(),
        ),
      ),
    );
  }

  /// 频道点击：已实现的跳页，未实现的居中提示
  void _onTap(BuildContext context, _NavItem item) {
    switch (item.tag) {
      case 'weather':
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const WeatherScreen()),
        );
        return;
      case 'spot':
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const SpotsScreen()),
        );
        return;
      case 'catch':
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const CatchScreen()),
        );
        return;
      case 'shop':
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const MallScreen()),
        );
        return;
      case 'lure':
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const LureScreen()),
        );
        return;
      case 'skill':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const ArticleListScreen(
              title: '垂钓技巧',
              tabs: [ArticleTab('技巧', 'skill')],
            ),
          ),
        );
        return;
      case 'event':
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ActivityListScreen()),
        );
        return;
      default:
        CenterToast.show(context, '「${item.label}」功能未开发');
    }
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  final String tag;
  const _NavItem(this.icon, this.label, this.tag);
}

class _GridCell extends StatelessWidget {
  final _NavItem item;
  final VoidCallback onTap;
  const _GridCell({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: AppTheme.primaryLight,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(item.icon, color: AppTheme.primary, size: 24),
          ),
          const SizedBox(height: 6),
          Text(item.label,
              style: const TextStyle(
                  fontSize: 12, color: AppTheme.textPrimary)),
        ],
      ),
    );
  }
}
