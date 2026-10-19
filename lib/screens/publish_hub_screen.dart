import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../services/session_provider.dart';
import '../widgets/center_toast.dart';
import 'auth_screen.dart';
import 'publish_screen.dart';
import 'publish_venue_screen.dart';
import 'publish_spot_screen.dart';
import 'watermark_camera_screen.dart';

/// 发布类别中心：点击底部「+」后弹出
/// 9 个入口：渔获 / 拍照打卡 / 问答 / 说说 / 出售二手 / 求购二手 / 加钓场 / 加渔具店 / 标记野钓点
class PublishHubScreen extends StatelessWidget {
  const PublishHubScreen({super.key});

  /// 类别定义：图标 / 名称 / 副标题 / 主题色
  static const List<_HubItem> _items = [
    _HubItem('post', Icons.phishing, '发布渔获', '晒渔获晒鱼情', AppTheme.primary),
    _HubItem('camera', Icons.photo_camera_outlined, '拍照打卡', '照片带时间天气水印', AppTheme.warning),
    _HubItem('ask', Icons.help_outline, '钓鱼问答', '有问题大家帮', AppTheme.accent),
    _HubItem('say', Icons.chat_bubble_outline, '随便说说', '点滴心情随记', AppTheme.violet),
    _HubItem('sell', Icons.sell_outlined, '出售二手', '闲置渔具变现', AppTheme.danger),
    _HubItem('buy', Icons.shopping_cart_outlined, '求购二手', '发布求购需求', AppTheme.star),
    _HubItem('venue', Icons.storefront_outlined, '加钓场', '审核后展示', AppTheme.primaryDark),
    _HubItem('shop', Icons.store_outlined, '加渔具店', '审核后展示', AppTheme.indigo),
    _HubItem('wild', Icons.add_location_alt_outlined, '标记野钓点', '地图全员可见', AppTheme.deepOrange),
  ];

  void _open(BuildContext context, String key) {
    // 未登录：先提示再带去登录页，不进入任何发布表单
    // （在入口处拦一次，比进到表单填完再被弹回来体验好得多）
    final sp = Provider.of<SessionProvider>(context, listen: false);
    if (!sp.isLoggedIn) {
      CenterToast.show(context, '请先登录后再发布', icon: Icons.lock_outline);
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const AuthScreen()),
      );
      return;
    }

    Widget page;
    switch (key) {
      case 'camera':
        page = const WatermarkCameraScreen();
        break;
      case 'post':
      case 'ask':
      case 'say':
      case 'sell':
      case 'buy':
        page = PublishScreen(category: key);
        break;
      case 'venue':
        page = const PublishVenueScreen(kind: 'venue');
        break;
      case 'shop':
        page = const PublishVenueScreen(kind: 'shop');
        break;
      default: // wild
        page = const PublishSpotScreen();
        break;
    }
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => page),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('选择发布类别'),
        elevation: 0,
      ),
      body: Column(
        children: [
          // 顶部引导
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              gradient: AppTheme.brandGradient,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Row(
              children: [
                Icon(Icons.explore, color: Colors.white, size: 30),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('分享你的钓鱼生活',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold)),
                      SizedBox(height: 3),
                      Text('发动态 / 问问题 / 淘二手 / 标钓点',
                          style: TextStyle(
                              color: Colors.white70, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // 八宫格
          Expanded(
            child: GridView.count(
              padding: const EdgeInsets.all(16),
              crossAxisCount: 4,
              mainAxisSpacing: 12,
              crossAxisSpacing: 10,
              childAspectRatio: 0.78,
              children: _items.map((item) => _hubCell(context, item)).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _hubCell(BuildContext context, _HubItem item) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => _open(context, item.key),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 图标底
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: AppTheme.categorySoft(item.key),
              borderRadius: BorderRadius.circular(17),
            ),
            child: Icon(item.icon, color: item.color, size: 27),
          ),
          const SizedBox(height: 7),
          Text(item.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary)),
          const SizedBox(height: 2),
          Text(item.sub,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 10, color: AppTheme.textSecondary)),
        ],
      ),
    );
  }
}

class _HubItem {
  final String key;
  final IconData icon;
  final String name;
  final String sub;
  final Color color;
  const _HubItem(this.key, this.icon, this.name, this.sub, this.color);
}
