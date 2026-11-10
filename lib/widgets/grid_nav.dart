import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models/home_layout.dart';
import '../screens/activity_list_screen.dart';
import '../screens/article_list_screen.dart';
import '../screens/catch_screen.dart';
import '../screens/fish_guide_screen.dart';
import '../screens/lure_screen.dart';
import '../screens/mall_screen.dart';
import '../screens/member_center_screen.dart';
import '../screens/nearby_anglers_screen.dart';
import '../screens/pond_screen.dart';
import '../screens/signin_screen.dart';
import '../screens/spots_screen.dart';
import '../screens/weather_screen.dart';
import '../utils/home_icons.dart';
import 'center_toast.dart';

/// 首页宫格导航（v46：内容与列数全部由后台 `/home/layout` 下发）
///
/// 和老版本的区别：
///   · 老的 10 个入口是写死的 const 列表，改一个名字就要发版；
///     现在名字、图标、顺序、显示与否都在后台「首页分类导航」里配。
///   · 一行几个也由后台决定（4 或 5），窄屏机型嫌挤可以切 4 个。
///   · 后台删掉 / 隐藏分类后，App 按接口返回的列表渲染，不再有「幽灵入口」。
///
/// 兜底：接口没数据时用 [HomeLayout.fallback]（= 改版前那 10 个），
/// 所以断网也不会出现空宫格。
class GridNav extends StatelessWidget {
  final List<HomeCategory> items;

  /// 一行几个（4 / 5），由后台配置
  final int crossAxisCount;

  const GridNav({
    super.key,
    this.items = const [],
    this.crossAxisCount = 5,
  });

  @override
  Widget build(BuildContext context) {
    final list = items.isEmpty ? HomeLayout.fallback.categories : items;
    final cols = (crossAxisCount == 4) ? 4 : 5;

    return Card(
      margin: const EdgeInsets.symmetric(
          horizontal: AppTheme.pagePad, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
        child: GridView.count(
          crossAxisCount: cols,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          // ★ v2.1.92：必须显式给 zero。
          //
          //   GridView 的 `padding` 传 null 时，Flutter 会自动套用
          //   `MediaQuery.padding`（见 ScrollView 的 `_effectivePadding`）：
          //   卡片组于是被垫上「状态栏 44 + 底部 34 = 78pt」的空白。
          //   两行还好、只显得松；后台只配 5 个（一行）时，上面那 44pt 和
          //   下面的 12pt 一对比，就是用户截图里「上面留空太多了」。
          //   显式归零后，上下只由外层 Padding 的 12 决定，单行/多行都对称。
          padding: EdgeInsets.zero,
          // 4 个一行时格子更宽，比例跟着调，图标才不会被拉成扁的
          childAspectRatio: cols == 4 ? 0.92 : 0.85,
          children: list
              .map((c) => _GridCell(
                    item: c,
                    big: cols == 4,
                    onTap: () => openCategory(context, c),
                  ))
              .toList(),
        ),
      ),
    );
  }

  /// 分类点击：按后台配的 tag 跳 App 内页面
  void openCategory(BuildContext context, HomeCategory item) {
    if (item.action == 'none') {
      CenterToast.show(context, '「${item.name}」暂未开放');
      return;
    }
    final route = routeOf(item.value);
    if (route == null) {
      CenterToast.show(context, '「${item.name}」功能未开发');
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => route));
  }

  /// tag → 页面（纯函数，单测直接断言）
  ///
  /// ★ 后台 `lib/home_layout.php` 的 `home_action_catalog()` 必须和这里同步：
  ///   后台给了个这里没有的 tag，用户点了只会看到「功能未开发」。
  static Widget? routeOf(String tag) {
    switch (tag) {
      case 'weather':
        return const WeatherScreen();
      case 'spot':
        return const SpotsScreen();
      case 'catch':
        return const CatchScreen();
      case 'lure':
        return const LureScreen();
      case 'skill':
        return const ArticleListScreen(
          title: '垂钓技巧',
          tabs: [ArticleTab('技巧', 'skill')],
        );
      case 'event':
        return const ActivityListScreen();
      case 'shop':
        return const MallScreen();
      case 'pond':
        return const PondScreen();
      case 'guide':
        return const FishGuideScreen();
      case 'nearby':
        return const NearbyAnglersScreen();
      case 'signin':
        return const SigninScreen();
      case 'member':
        return const MemberCenterScreen();
      default:
        // blackpit / gear / live 等还没有对应页面 → 返回 null 走提示
        return null;
    }
  }
}

class _GridCell extends StatelessWidget {
  final HomeCategory item;
  final bool big;
  final VoidCallback onTap;

  const _GridCell({required this.item, required this.onTap, this.big = false});

  @override
  Widget build(BuildContext context) {
    final box = big ? 50.0 : 44.0;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: box,
            height: box,
            decoration: BoxDecoration(
              color: AppTheme.primarySoft,
              borderRadius: BorderRadius.circular(big ? 16 : 14),
            ),
            clipBehavior: Clip.antiAlias,
            child: _icon(box),
          ),
          SizedBox(height: big ? 7 : 6),
          Text(
            item.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: big ? 12.5 : 12,
              fontWeight: FontWeight.w500,
              color: AppTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _icon(double box) {
    final url = item.iconUrl;
    if (url != null && url.isNotEmpty) {
      // 后台传的自定义图标：铺满方块，加载失败退回内置图标（不留白块）
      return Image.network(
        url,
        width: box,
        height: box,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _builtinIcon(box),
      );
    }
    return _builtinIcon(box);
  }

  Widget _builtinIcon(double box) => Icon(
        homeIconOf(item.icon),
        size: box * 0.5,
        color: AppTheme.primary,
      );
}
