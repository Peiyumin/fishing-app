import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../services/session_provider.dart';
import '../widgets/center_toast.dart';
import 'auth_screen.dart';
import 'publish_catch_screen.dart';
import 'publish_screen.dart';
import 'publish_venue_screen.dart';
import 'publish_spot_screen.dart';

/// 发布类别中心：点击底部「+」后弹出
/// 8 个入口：渔获 / 问答 / 说说 / 出售二手 / 求购二手 / 加钓场 / 加渔具店 / 标记野钓点
/// 说明：原「拍照打卡」已并入渔获发布页（发布渔获时直接调打卡相机带水印）
class PublishHubScreen extends StatelessWidget {
  const PublishHubScreen({super.key});

  /// 类别定义：图标 / 名称 / 副标题
  ///
  /// 不再给每类配一个主题色：一屏八个高饱和图标是「不协调」的根源，
  /// 设计稿只有近黑 + 一个荧光黄绿，类别靠图标形状 + 名称区分就够了。
  static const List<_HubItem> _items = [
    _HubItem('post', Icons.phishing, '发布渔获', '晒渔获晒鱼情'),
    _HubItem('ask', Icons.help_outline, '钓鱼问答', '有问题大家帮'),
    _HubItem('say', Icons.chat_bubble_outline, '随便说说', '点滴心情随记'),
    _HubItem('sell', Icons.sell_outlined, '出售二手', '闲置渔具变现'),
    _HubItem('buy', Icons.shopping_cart_outlined, '求购二手', '发布求购需求'),
    _HubItem('venue', Icons.storefront_outlined, '加钓场', '审核后展示'),
    _HubItem('shop', Icons.store_outlined, '加渔具店', '审核后展示'),
    _HubItem('wild', Icons.add_location_alt_outlined, '标记野钓点', '地图全员可见'),
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
      case 'post':
        // 渔获走独立发布页（自动定位 + 公开开关 + 水印相机 + 鱼种）
        page = const PublishCatchScreen();
        break;
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
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: const Text('选择发布类别')),
      body: Column(
        children: [
          // 顶部引导（整页唯一的重色块）
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            decoration: BoxDecoration(
              gradient: AppTheme.brandGradient,
              borderRadius: BorderRadius.circular(AppTheme.radiusLg),
            ),
            child: const Row(
              children: [
                Icon(Icons.explore, color: Colors.white, size: 28),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('分享你的钓鱼生活',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700)),
                      SizedBox(height: 3),
                      Text('发动态 / 问问题 / 淘二手 / 标钓点',
                          style: TextStyle(
                              color: Colors.white60, fontSize: 11.5)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // 八宫格
          //
          // v2.1.59：原来是「图标 + 两行文字」直接摊在灰底上，没有任何容器；
          // 且「出售二手」单独套了一层浅红底（categorySoft 的历史残留），
          // 八个格子里只有一个带色块，看着像被误选中的按钮。
          // 现在八格统一白卡 + 统一近黑图标，色相只由图标形状区分。
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
              physics: const BouncingScrollPhysics(),
              itemCount: _items.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 0.92,
              ),
              itemBuilder: (_, i) => _hubCell(context, _items[i]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _hubCell(BuildContext context, _HubItem item) {
    return Material(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        onTap: () => _open(context, item.key),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            border: Border.all(color: AppTheme.border),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(item.icon, color: AppTheme.primary, size: 24),
              const SizedBox(height: 7),
              Text(item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary)),
              const SizedBox(height: 2),
              Text(item.sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 9.5, color: AppTheme.textTertiary)),
            ],
          ),
        ),
      ),
    );
  }
}

class _HubItem {
  final String key;
  final IconData icon;
  final String name;
  final String sub;
  const _HubItem(this.key, this.icon, this.name, this.sub);
}
