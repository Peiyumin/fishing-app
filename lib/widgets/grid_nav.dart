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

  /// 卡片内框的上下留白。
  ///
  /// ★ v2.1.93：**图标上方与文字下方必须一样多**，所以这个数只在这里出现
  ///   一次，上下都用它。之前是交给 `GridView` 的 `childAspectRatio` 反推
  ///   格子高度，格子比内容高出来的部分归 `Column` 的居中管 —— 一旦比例和
  ///   实际字体行高对不上，多出来的空白就全堆在图标上方（用户量过：
  ///   实物上留白 67.6pt、下留白 18pt，差 49pt）。
  static const double padV = 14;

  /// 一行文字的行高（见 [_GridCell] 里的 `height: 1.1`）
  ///
  /// ★ 为什么是 1.1 而不是常见的 1.35：`TextStyle.height` 多出来的行距，
  ///   Flutter 默认**全部加在字形上方**，等于「文字往下挪」——
  ///   图标与文字之间的空隙变大、文字到卡片底边却只剩一点点，
  ///   看起来又是「上大下小」。1.1 基本只剩 ascent/descent 本身，
  ///   上下才真的对得上（实测差 1pt 以内）。
  static double _labelH(bool big) => (big ? 12.5 : 12) * 1.1;

  @override
  Widget build(BuildContext context) {
    final list = items.isEmpty ? HomeLayout.fallback.categories : items;
    final cols = (crossAxisCount == 4) ? 4 : 5;
    final big = cols == 4;

    // ── 尺寸全部由内容算出来，不再让网格去猜 ──
    //
    //  v2.1.93 之前用 `GridView.count + childAspectRatio`：
    //    · 格子高度 = 格宽 / 比例，和「图标 44 + 间距 6 + 文字行高」没有关系；
    //    · 多出来的高度由 Column 居中吸收，看着像是"应该对称"，
    //      可比例一旦和字体行高对不上，多余部分就整块堆到上面去；
    //    · `padding` 传 null 还会被自动套上 `MediaQuery.padding`（v2.1.92 的坑）。
    //  现在干脆不用 GridView：格子高度 = 内容高度，卡片上下各留 [padV]，
    //  上留白和下留白在构造上就不可能不相等。
    final box = big ? 50.0 : 44.0;
    final gap = big ? 7.0 : 6.0;
    // +0.5 是排版浮点的余量：文字实际行高会按 1/64 像素取整，
    // 差 0.125px 就会触发 RenderFlex overflow（4 列时实测会报）。
    // 内容居中，多出的这 0.5 上下各分 0.25，对称性不受影响。
    final cellH = box + gap + _labelH(big) + 0.5;

    final rows = <List<HomeCategory>>[];
    for (var i = 0; i < list.length; i += cols) {
      rows.add(list.sublist(
          i, i + cols > list.length ? list.length : i + cols));
    }

    return Card(
      margin: const EdgeInsets.symmetric(
          horizontal: AppTheme.pagePad, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, padV, 6, padV),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var r = 0; r < rows.length; r++) ...[
              if (r > 0) const SizedBox(height: 12),
              SizedBox(
                height: cellH,
                child: Row(
                  children: [
                    for (var c = 0; c < cols; c++)
                      Expanded(
                        child: c < rows[r].length
                            ? _GridCell(
                                item: rows[r][c],
                                big: big,
                                onTap: () => openCategory(context, rows[r][c]),
                              )
                            : const SizedBox.shrink(),
                      ),
                  ],
                ),
              ),
            ],
          ],
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
        // 内容高度 == 格子高度（见 build 里的 cellH），居中只是兜底；
        // `min` 保证格子即使被别处撑高，内容也不会被拉散。
        mainAxisSize: MainAxisSize.min,
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
              // 行高写死：`_labelH()` 按 1.1 算格子高度，这里必须同一个数，
              // 否则一改字体行高，上下留白又会对不上。
              height: 1.1,
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
