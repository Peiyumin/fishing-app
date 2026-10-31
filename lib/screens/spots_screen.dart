import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../widgets/ui_kit.dart';

import '../models/fishing_spot.dart';
import '../services/location_service.dart';
import '../services/map_config_service.dart';
import '../services/session_provider.dart';
import '../services/spot_service.dart';
import '../utils/coord_transform.dart';
import '../widgets/center_toast.dart';
import '../widgets/location_prompt.dart';
import 'auth_screen.dart';
import 'publish_spot_screen.dart';
import 'publish_shop_screen.dart';
import 'publish_venue_screen.dart';
import 'shop_detail_screen.dart';
import 'spot_detail_screen.dart';
import 'spot_map_gl.dart';
import 'spot_map_screen.dart';
import '../widgets/app_refresh.dart';

/// 钓点页：三 Tab（v2.1.39 起渔具店从「本地钓场」筛选里独立成一级入口）
///   ① 本地钓场：图2 样式卡片列表（封面 / 星级 / 标签 / 地址 / 距离 / 收费 / 简介）
///   ② 野钓钓点：卫星地图（高德卫星 + 路网），用户可在地图上添加标记，全员实时可见
///   ③ 渔具店：渔具店列表 → 点进独立的渔具店详情页（店内店外图 / 售卖种类 /
///      具体位置 / 是否外送 / 顾客评价 / 导航调起本机地图 App）
class SpotsScreen extends StatefulWidget {
  /// 打开时预选的钓场类型（「路亚」页会带 '路亚' 进来直接过滤）
  final String initialType;
  const SpotsScreen({super.key, this.initialType = '全部'});

  @override
  State<SpotsScreen> createState() => _SpotsScreenState();
}

class _SpotsScreenState extends State<SpotsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final SpotMapController _mapCtrl = SpotMapController();

  List<FishingSpot> _venues = []; // 本地钓场（kind=venue）
  List<FishingSpot> _shops = []; // 渔具店（kind=shop）
  List<FishingSpot> _wild = []; // 野钓点（kind=wild）
  bool _loading = true;
  bool _locating = false; // 正在定位（按钮转圈，避免「点了没反应」的错觉）
  bool _refreshing = false; // 正在手动刷新钓点（刷新按钮转圈）
  // ★ 「野钓场」已删除（用户要求）：野钓点有独立 Tab，本地钓场再留这个类型
  //   只会让两套数据混在一起。
  // ★ 「渔具店」也从筛选里移走 —— 它现在是一级 Tab，和钓场不是一回事。
  final List<String> _types = ['全部', '黑坑', '路亚', '海钓'];
  late String _type =
      _types.contains(widget.initialType) ? widget.initialType : '全部';

  // 我的当前位置（WGS-84，用于距离计算）
  double? _myLat;
  double? _myLng;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    // 左右滑动切换时同步胶囊高亮
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    _load();
    // 先拉后台地图配置（决定用原生 GL 还是 flutter_map 内核），拉到了再重建
    MapConfigService.load().then((_) {
      if (mounted) setState(() {});
    });
    // 首帧后再定位：避免在 Flutter 首帧之前就弹系统权限框（iOS 会吞掉），
    // 也不至于在没有地图实例时去操作 MapController。
    WidgetsBinding.instance.addPostFrameCallback((_) => _locate(silent: true));
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// 拉钓点数据
  ///
  /// [feedback] = true 只给「用户手动点刷新」用：按钮转圈 + 结果 toast。
  ///
  /// ★★ 「刷新按钮点了没反应」的真因（不是点击没接上）：
  ///   ① 数据没变化时，界面本来就不会有任何变化 —— 钓点数一样、地图上的点
  ///      也一样，肉眼无从判断"到底刷没刷"；
  ///   ② 整条链路（按钮 → 请求 → setState）全程没有任何 loading 或提示。
  ///   两件事叠在一起，手感就等于"按钮坏了"。所以现在：按下立刻转圈、
  ///   回来弹一句结果，哪怕一个点都没变，也能确认它真的跑了。
  Future<void> _load({bool feedback = false}) async {
    if (feedback && mounted) setState(() => _refreshing = true);
    try {
      final spots = await SpotService.fetchSpots();
      if (!mounted) return;
      final wild = spots.where((s) => s.kind == 'wild').toList();
      setState(() {
        _venues = spots.where((s) => s.kind == 'venue').toList();
        _shops = spots.where((s) => s.kind == 'shop').toList();
        _wild = wild;
        _loading = false;
      });
      if (feedback && mounted) {
        CenterToast.show(
          context,
          wild.isEmpty
              ? '已刷新，暂时还没有钓友共享的钓点'
              : '已刷新 · 共 ${wild.length} 个野钓钓点',
          icon: Icons.refresh,
        );
      }
    } catch (e) {
      // ★ 失败也要把 _loading 放下来：否则三个 Tab 会一直转圈（空列表 + 永真 loading），
      //   看起来像"卡死了"，实际是网络挂了。
      if (mounted) setState(() => _loading = false);
      if (feedback && mounted) {
        CenterToast.show(context, '刷新失败：$e',
            icon: Icons.cloud_off_outlined);
      }
    } finally {
      if (mounted && feedback) setState(() => _refreshing = false);
    }
  }

  /// 获取当前位置（仅用于距离展示与地图居中）
  ///
  /// [silent] = true 用于「打开页面自动定位」：失败不打扰用户。
  /// 手动点「我的位置」按钮时 silent=false：转圈 + 结果 toast + 失败弹窗引导。
  Future<void> _locate({bool silent = false}) async {
    if (_locating) return; // 防连点重复请求（并发会把 iOS 权限框顶掉）
    if (mounted) setState(() => _locating = true);
    try {
      final pos = await LocationService.determinePosition();
      if (!mounted) return;
      setState(() {
        _myLat = pos.latitude;
        _myLng = pos.longitude;
      });
      // 卫星地图居中到当前位置
      // 野钓 Tab 还没渲染时地图实例不存在，controller 内部的 _move 为空，调用无副作用
      _mapCtrl.moveToLocation(pos.latitude, pos.longitude);
      if (!silent && mounted) {
        CenterToast.show(context, '已定位到当前位置', icon: Icons.my_location);
      }
    } on LocationException catch (e) {
      if (mounted && !silent) LocationPrompt.showError(context, e);
    } catch (e) {
      if (mounted && !silent) {
        CenterToast.show(context, '定位失败：$e', icon: Icons.location_off_outlined);
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  /// 与我的位置的距离文案（拿不到定位时返回 null）
  String? _distanceText(FishingSpot s) {
    if (_myLat == null || _myLng == null) return null;
    final m = CoordTransform.distanceMeters(
        _myLat!, _myLng!, s.lat, s.lng);
    return CoordTransform.formatDistance(m);
  }

  /// 本地钓场 Tab 展示：只放钓场（kind=venue），渔具店已独立成 Tab
  List<FishingSpot> get _visibleVenues {
    if (_type == '全部') return _venues;
    return _venues.where((s) => s.type == _type).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('钓点'),
        // 头部高度与其他主 Tab 统一（首页 46，发现 44 + 44）
        toolbarHeight: 46,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(44),
          child: Container(
            color: Colors.white,
            child: Row(
              children: [
                _tabChip(0, '本地钓场（${_venues.length}）'),
                _tabChip(1, '野钓钓点'),
                _tabChip(2, '渔具店（${_shops.length}）'),
              ],
            ),
          ),
        ),
        actions: [
          // 右上角「+」按当前 Tab 分流（v2.1.55）：
          //   本地钓场 → 添加钓场表单
          //   野钓钓点 → 标记野钓点（地图选点，免审核）
          //   渔具店   → 添加渔具店表单（店名/门店·流动/饵料·鱼竿·鱼线/可配送）
          IconButton(
            icon: Icon(_addIcon),
            tooltip: _addLabel,
            onPressed: _openAddForm,
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        // ★ 禁止左右滑动切页，只能用顶部胶囊切换。
        //   两个原因：
        //   ① 第 2 个 Tab 是原生 GL 地图（Flutter PlatformView），横向拖动
        //      会被 TabBarView 的滚动识别器抢走，地图既拖不动也会卡在
        //      「手势被截一半」的状态；
        //   ② 产品上地图页需要整屏响应拖动 / 双指缩放，不能有翻页手势。
        physics: const NeverScrollableScrollPhysics(),
        children: [
          _TabKeepAlive(child: _buildVenueTab()),
          _TabKeepAlive(child: _buildWildTab()),
          _TabKeepAlive(child: _buildShopTab()),
        ],
      ),
    );
  }

  /// 顶部 Tab 胶囊（与「发现」页同款，替代默认 TabBar 让头部高度统一）
  Widget _tabChip(int index, String label) {
    final selected = _tabController.index == index;
    return Expanded(
      child: InkWell(
        onTap: () {
          if (selected) return;
          _tabController.animateTo(index);
          setState(() {});
        },
        child: Container(
          height: 44,
          alignment: Alignment.center,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: selected ? AppTheme.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
            ),
            // 三颗胶囊平分宽度后只有 ~110px，窄屏（320）上「本地钓场（12）」
            // 会顶到边界。FittedBox 让它按需缩字，绝不溢出。
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? Colors.white : AppTheme.textSecondary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ==================== Tab ① 本地钓场 ====================
  Widget _buildVenueTab() {
    return Column(
      children: [
        // 类型筛选
        SizedBox(
          // v2.1.61：46 → 42（胶囊本身 30 左右，之前上下各留 8pt 空）
          height: 42,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppTheme.pagePad),
            children: _types
                .map((t) => Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(t),
                        selected: _type == t,
                        onSelected: (_) => setState(() => _type = t),
                      ),
                    ))
                .toList(),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: AppRefresh(
            onRefresh: _load,
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _visibleVenues.isEmpty
                    ? ListView(children: const [
                        SizedBox(height: 80),
                        Center(child: Text('暂无相关内容')),
                        SizedBox(height: 8),
                        Center(
                          child: Text('点右上角「+」提交钓场，审核通过后展示',
                              style: TextStyle(
                                  fontSize: 12, color: AppTheme.textTertiary)),
                        ),
                      ])
                    : ListView.separated(
                        // v2.1.61：卡与卡 8 → 6，底部 16 → 12
                        padding: const EdgeInsets.only(top: 6, bottom: 12),
                        itemCount: _visibleVenues.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 6),
                        itemBuilder: (_, i) => _venueCard(_visibleVenues[i]),
                      ),
          ),
        ),
      ],
    );
  }

  /// 图2 样式钓场卡片：封面 / 名称 / 标签 / 星级 / 地址距离 / 鱼种 / 收费 / 简介
  /// 钓点卡（列表页）
  ///
  /// v2.1.59 重排：原来一屏塞了「名称 / 标签 / 地址 / 鱼种 / 门票 / 描述」六行，
  /// 每行前面一个彩色 emoji（📍🐟🎣📝），是整页最「花」的地方；
  /// 缩略图固定 96 高，却被六行文字撑到 150 多，图和字完全不成比例。
  /// 现在压成四行 —— 名称+评分 / 标签 / 地址+距离 / 门票+评论数，
  /// 图标一律用 Material 线性图标（textTertiary），描述留给详情页。
  ///
  /// v2.1.60：缩略图改回**固定 96×96**（v2.1.59 用按内容撑高，结果一卡一个
  /// 图高），行距从 7/9/5 压到 3/3/2 —— 一屏能多露小半张卡。
  Widget _venueCard(FishingSpot s) {
    final tags = s.tags
        .split(',')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .take(3)
        .toList();
    final distance = _distanceText(s);
    return Container(
      // v2.1.61：左右 12 → pagePad，底部 10 交给列表的 separator（不重复留白）
      margin: const EdgeInsets.symmetric(horizontal: AppTheme.pagePad),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(color: AppTheme.border),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _openDetail(s),
          child: Padding(
            padding: const EdgeInsets.all(10),
            // 固定 96×96 的缩略图：四张卡的图必须一样大
            //（之前那套「按内容撑高」会让图跟着文字高度伸缩，一卡一个高度）
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // 封面：固定 96×96 —— 所有卡片的图一样大，不再跟着文字高度伸缩
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                  child: SizedBox(
                    width: 96,
                    height: 96,
                    child: s.coverUrl != null
                        ? Image.network(
                            s.coverUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _venueThumb(),
                          )
                        : _venueThumb(),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ① 名称 + 评分
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              s.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 15,
                                  height: 1.2,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.textPrimary),
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Icon(Icons.star_rounded,
                              size: 13, color: AppTheme.star),
                          const SizedBox(width: 1),
                          Text(
                            s.rating.toStringAsFixed(1),
                            style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textSecondary),
                          ),
                        ],
                      ),
                      // ② 标签：推荐走淡黄绿，其余中性灰 —— 一屏最多一个强调色
                      if (tags.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Wrap(
                          spacing: 5,
                          runSpacing: 4,
                          children: tags
                              .map((t) => UiTag(t,
                                  tone: t.contains('推荐')
                                      ? UiTagTone.accent
                                      : UiTagTone.neutral))
                              .toList(),
                        ),
                      ],
                      const SizedBox(height: 3),
                      // ③ 地址 + 距离
                      Row(
                        children: [
                          const Icon(Icons.place_outlined,
                              size: 12.5, color: AppTheme.textTertiary),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(
                              s.address.isNotEmpty ? s.address : '地址待补充',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 11.5, color: AppTheme.textSecondary),
                            ),
                          ),
                          if (distance != null) ...[
                            const SizedBox(width: 6),
                            Text(distance,
                                style: const TextStyle(
                                    fontSize: 11,
                                    color: AppTheme.textTertiary)),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      // ④ 门票 + 评论数
                      Row(
                        children: [
                          const Icon(Icons.local_offer_outlined,
                              size: 12, color: AppTheme.textTertiary),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(
                              s.fee.isNotEmpty ? s.fee : '收费待补充',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 11.5, color: AppTheme.textSecondary),
                            ),
                          ),
                          const Icon(Icons.mode_comment_outlined,
                              size: 11.5, color: AppTheme.textTertiary),
                          const SizedBox(width: 3),
                          Text('${s.commentCount}',
                              style: const TextStyle(
                                  fontSize: 11, color: AppTheme.textTertiary)),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 无封面时的占位（浅灰底 + 近黑钓钩，不用纯灰块）
  Widget _venueThumb() => Container(
        color: AppTheme.primarySoft,
        alignment: Alignment.center,
        child: const Icon(Icons.phishing,
            size: 22, color: AppTheme.textTertiary),
      );

  /// 竖排文字：每个汉字一行（中文竖排没有原生排版，用一列 Text 最稳）
  List<Widget> _vChars(String s, {double size = 12, FontWeight w = FontWeight.w600}) {
    return s
        .split('')
        .where((c) => c.trim().isNotEmpty)
        .map((c) => Text(c,
            style: TextStyle(
                fontSize: size,
                height: 1.18,
                fontWeight: w,
                color: AppTheme.textPrimary)))
        .toList();
  }

  /// 竖排条里的「图标 + 中文」按钮
  /// 竖排信息条里的小按钮
  ///
  /// ★ 外面必须包一层 `Material(type: transparency)`：父级 Container 有不透明
  ///   底色，水波纹是画在**祖先 Material 上**的，会被这层底色整个盖住 ——
  ///   于是按下去毫无反馈，看起来就像"按钮没反应"。包一层透明 Material 后，
  ///   水波纹画在这层底色之上，点下去立刻有色块扩散。
  Widget _vAction(IconData icon, String label, Color color,
      {required VoidCallback onTap, bool busy = false}) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: busy ? null : onTap,
        borderRadius: BorderRadius.circular(8),
        splashColor: color.withOpacity(0.14),
        highlightColor: color.withOpacity(0.07),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (busy)
                SizedBox(
                  width: 17,
                  height: 17,
                  child: CircularProgressIndicator(strokeWidth: 2, color: color),
                )
              else
                Icon(icon, size: 17, color: color),
              const SizedBox(height: 2),
              Text(label,
                  style: TextStyle(
                      fontSize: 10.5, height: 1.1, color: color)),
            ],
          ),
        ),
      ),
    );
  }

  /// 去标记野钓点（未登录先登录）
  Future<void> _openPublishSpot() async {
    if (!await _requireLogin()) return;
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PublishSpotScreen()),
    );
    _load(); // 返回后刷新：新标记全员实时可见
  }

  Widget _buildWildTab() {
    return Stack(
      children: [
        // 地图本体（嵌入模式：顶部无搜索栏、底部统计条由水面/钓点/渔获胶囊承担）
        Positioned.fill(
          // 渲染内核：默认原生 MapLibre（GPU、自带瓦片缓存，拖动不卡），
          // 后台「地图底图 → 渲染内核」可切回 flutter_map 兜底
          child: MapConfigService.useNativeEngine
              ? SpotMapGlScreen(
                  embedded: true,
                  extraSpots: _wild,
                  controller: _mapCtrl,
                )
              : SpotMapScreen(
                  embedded: true,
                  extraSpots: _wild,
                  controller: _mapCtrl,
                ),
        ),
        // 左侧竖排信息条（不再横着压在标准图上方，视野让给地图）
        Positioned(
          left: 12,
          // 让开地图自带的「图层 / 禁钓名录」两个圆按钮
          top: 62,
          child: Container(
            width: 48,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.94),
              borderRadius: BorderRadius.circular(14),
              boxShadow: const [
                BoxShadow(color: Colors.black12, blurRadius: 6)
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 竖排：钓 / 友 / 共 / 享 一列往下
                ..._vChars('钓友共享'),
                const SizedBox(height: 3),
                Text('${_wild.length}',
                    style: const TextStyle(
                        fontSize: 15,
                        height: 1.1,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.primary)),
                const Text('个',
                    style: TextStyle(fontSize: 11, height: 1.2)),
                const SizedBox(height: 8),
                Container(width: 22, height: 1, color: const Color(0x14000000)),
                const SizedBox(height: 8),
                // 刷新（图标 + 中文）：按下即转圈，回来弹「共 N 个」
                _vAction(Icons.refresh, '刷新', AppTheme.textSecondary,
                    busy: _refreshing,
                    onTap: () => _load(feedback: true)),
                const SizedBox(height: 10),
                // 标记（图标 + 中文，主入口）
                _vAction(Icons.add_location_alt, '标记', AppTheme.danger,
                    onTap: _openPublishSpot),
              ],
            ),
          ),
        ),
        // ★ 右下角「我的位置」悬浮按钮已删除（用户反馈挡住地图、且与地图
        //   右上角工具条里的「定位」圆按钮重复）。重新定位请点右上角「定位」。
      ],
    );
  }

  // ==================== Tab ③ 渔具店 ====================
  //
  // 渔具店原来混在「本地钓场」的类型筛选里（选「渔具店」才出结果），
  // 用户反馈这样找不到店，所以提成一级 Tab：
  //   列表 → 点一条 → ShopDetailScreen（店内店外图 / 售卖种类 / 具体位置 /
  //   是否外送 / 顾客评价 / 导航调起本机地图 App）
  Widget _buildShopTab() {
    // ★ 有数据时刷新不清空（和全站一致）：否则下拉一次闪一下白
    if (_loading && _shops.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    return AppRefresh(
      onRefresh: _load,
      child: _shops.isEmpty
          ? ListView(children: const [
              SizedBox(height: 84),
              Center(
                child: Icon(Icons.storefront_outlined,
                    size: 44, color: AppTheme.textSecondary),
              ),
              SizedBox(height: 10),
              Center(
                child: Text('附近还没有渔具店',
                    style: TextStyle(fontSize: 14, color: AppTheme.textSecondary)),
              ),
              SizedBox(height: 8),
              Center(
                child: Text('点右上角「+」提交渔具店，审核通过后展示',
                    style: TextStyle(fontSize: 12, color: AppTheme.textTertiary)),
              ),
            ])
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(0, 6, 0, 16),
              itemCount: _shops.length,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (_, i) => _shopCard(_shops[i]),
            ),
    );
  }

  /// 渔具店卡片：封面 / 店名 / 外送角标 / 星级 / 售卖种类 / 地址距离 / 评价数
  Widget _shopCard(FishingSpot s) {
    final cats = s.fish
        .split(RegExp(r'[,，、/|;；\s]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final distance = _distanceText(s);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: AppTheme.pagePad),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _openDetail(s, distanceText: distance),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 封面（尽量用店外照）
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 104,
                  height: 104,
                  child: s.coverUrl != null
                      ? Image.network(
                          s.coverUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: AppTheme.violetLight,
                            child: const Icon(Icons.storefront_outlined,
                                color: AppTheme.violet, size: 30),
                          ),
                        )
                      : Container(
                          color: AppTheme.violetLight,
                          child: const Icon(Icons.storefront_outlined,
                              color: AppTheme.violet, size: 30),
                        ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 店名 + 星级
                    Row(
                      children: [
                        Expanded(
                          child: Text(s.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.bold)),
                        ),
                        const Icon(Icons.star, size: 15, color: AppTheme.star),
                        const SizedBox(width: 3),
                        Text(s.rating.toStringAsFixed(1),
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.star)),
                      ],
                    ),
                    const SizedBox(height: 5),
                    // 外送 + 推荐/认证 角标
                    Wrap(
                      spacing: 5,
                      runSpacing: 4,
                      children: [
                        if (s.delivery)
                          _miniBadge('支持外送', AppTheme.primary,
                              AppTheme.primaryLight, Icons.delivery_dining),
                        if (s.tags.contains('推荐'))
                          _miniBadge('推荐', AppTheme.warning,
                              AppTheme.warningLight, Icons.thumb_up_alt_outlined),
                        if (s.tags.contains('认证'))
                          _miniBadge('电话认证', AppTheme.primary,
                              AppTheme.primaryLight, Icons.verified_outlined),
                      ],
                    ),
                    const SizedBox(height: 5),
                    // 售卖种类
                    Row(
                      children: [
                        const Icon(Icons.category_outlined,
                            size: 13, color: AppTheme.textTertiary),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            cats.isEmpty ? '经营范围待补充' : cats.join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 11.5, color: Colors.black54),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    // 地址 + 距离
                    Row(
                      children: [
                        const Icon(Icons.location_on_outlined,
                            size: 13, color: AppTheme.textTertiary),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            s.address.isNotEmpty ? s.address : '地址待补充',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 11.5, color: AppTheme.textTertiary),
                          ),
                        ),
                        if (distance != null) ...[
                          const SizedBox(width: 6),
                          Text(distance,
                              style: const TextStyle(
                                  fontSize: 11.5,
                                  color: AppTheme.textSecondary,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        const Icon(Icons.rate_review_outlined,
                            size: 12, color: AppTheme.textTertiary),
                        const SizedBox(width: 3),
                        Text('${s.commentCount} 条顾客评价',
                            style: const TextStyle(
                                fontSize: 11.5, color: AppTheme.textTertiary)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 小角标（外送 / 推荐 / 电话认证）
  Widget _miniBadge(String text, Color fg, Color bg, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: fg),
          const SizedBox(width: 2),
          Text(text,
              style: TextStyle(
                  fontSize: 9.5, height: 1.3, color: fg, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  void _openDetail(FishingSpot s, {String? distanceText}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => s.kind == 'shop'
            // 渔具店：独立详情页（店内店外图 / 售卖种类 / 外送 / 顾客评价…
            // 布局和钓场页完全不同，硬塞进 SpotDetailScreen 会两边都不像）
            ? ShopDetailScreen(spot: s, distanceText: distanceText)
            : SpotDetailScreen(spot: s),
      ),
    );
  }

  /// 添加钓场/渔具店（图4 表单，后台审核后展示）
  Future<void> _openVenueForm() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PublishVenueScreen()),
    );
    _load();
  }

  /// 右上角「+」的图标 / 提示随 Tab 变，避免用户以为永远是「加钓场」
  int get _tabIndex => _tabController.index;

  IconData get _addIcon {
    if (_tabIndex == 1) return Icons.add_location_alt_outlined;
    if (_tabIndex == 2) return Icons.storefront_outlined;
    return Icons.add_business_outlined;
  }

  String get _addLabel {
    if (_tabIndex == 1) return '标记野钓点';
    if (_tabIndex == 2) return '添加渔具店';
    return '添加钓场';
  }

  /// 按当前 Tab 打开对应的「添加」页面
  Future<void> _openAddForm() async {
    if (!await _requireLogin()) return;
    if (!mounted) return;
    switch (_tabController.index) {
      case 1:
        // 野钓钓点：地图选点 → 保存即全员可见
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const PublishSpotScreen()),
        );
        await _load();
        break;
      case 2:
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const PublishShopScreen()),
        );
        await _load();
        break;
      default:
        await _openVenueForm();
    }
  }

  /// 发布类操作统一前置校验：未登录提示并跳登录页
  /// 返回 true 表示已登录，可以继续；false 表示已跳转登录，调用方应中止
  Future<bool> _requireLogin() async {
    if (!mounted) return false;
    final sp = Provider.of<SessionProvider>(context, listen: false);
    if (sp.isLoggedIn) return true;
    CenterToast.show(context, '请先登录后再发布', icon: Icons.lock_outline);
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AuthScreen()),
    );
    // 登录成功后用户仍停在钓点页，需要自己再点一次发布
    return false;
  }
}

/// 让 TabBarView 的子页在切走后**不被销毁**。
///
/// 「野钓钓点」Tab 里挂的是原生 MapLibre PlatformView。TabBarView 内部是
/// PageView，离屏子页默认会被 dispose —— 于是每次从「本地钓场」切回地图，
/// 都要重新走一遍「创建原生 View → 解析样式 → 重新拉瓦片」，安卓上这一套
/// 3~8 秒，用户感受就是「地图每次进来都要转圈半天、加载完还闪一下」。
/// 用 AutomaticKeepAliveClientMixin 钉在树里，只有第一次要等。
class _TabKeepAlive extends StatefulWidget {
  final Widget child;
  const _TabKeepAlive({required this.child});

  @override
  State<_TabKeepAlive> createState() => _TabKeepAliveState();
}

class _TabKeepAliveState extends State<_TabKeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context); // keep-alive 协议要求：build 里必须先调
    return widget.child;
  }
}
