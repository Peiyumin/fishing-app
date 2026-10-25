import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';

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
import 'publish_venue_screen.dart';
import 'spot_detail_screen.dart';
import 'spot_map_gl.dart';
import 'spot_map_screen.dart';
import '../widgets/app_refresh.dart';

/// 钓点页：双 Tab
///   ① 本地钓场：图2 样式卡片列表（封面 / 星级 / 标签 / 地址 / 距离 / 收费 / 简介）
///   ② 野钓钓点：卫星地图（高德卫星 + 路网），用户可在地图上添加标记，全员实时可见
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
  final List<String> _types = ['全部', '黑坑', '路亚', '野钓场', '海钓', '渔具店'];
  late String _type =
      _types.contains(widget.initialType) ? widget.initialType : '全部';

  // 我的当前位置（WGS-84，用于距离计算）
  double? _myLat;
  double? _myLng;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
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

  /// 本地钓场 Tab 展示：钓场 + 渔具店（均审核后展示），按类型筛选
  List<FishingSpot> get _visibleVenues {
    final all = [..._venues, ..._shops];
    if (_type == '全部') return all;
    if (_type == '渔具店') {
      return _shops;
    }
    return all.where((s) => s.type == _type).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('钓点'),
        // 头部高度与其他主 Tab 统一（首页 46，发现 44 + 44）
        toolbarHeight: 46,
        flexibleSpace: Container(
          decoration: const BoxDecoration(gradient: AppTheme.headerGradient),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(44),
          child: Container(
            color: Colors.white,
            child: Row(
              children: [
                _tabChip(0, '本地钓场（${_venues.length + _shops.length}）'),
                _tabChip(1, '野钓钓点'),
              ],
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_business_outlined),
            tooltip: '添加钓场/渔具店',
            onPressed: () => _openVenueForm(),
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
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? Colors.white : AppTheme.textSecondary,
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
          height: 46,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: _types
                .map((t) => Padding(
                      padding: const EdgeInsets.only(right: 8),
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
                          child: Text('点右上角「+」提交钓场/渔具店，审核通过后展示',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey)),
                        ),
                      ])
                    : ListView.separated(
                        padding: const EdgeInsets.only(bottom: 16),
                        itemCount: _visibleVenues.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 8),
                        itemBuilder: (_, i) => _venueCard(_visibleVenues[i]),
                      ),
          ),
        ),
      ],
    );
  }

  /// 图2 样式钓场卡片：封面 / 名称 / 标签 / 星级 / 地址距离 / 鱼种 / 收费 / 简介
  Widget _venueCard(FishingSpot s) {
    final tags = s.tags
        .split(',')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();
    final distance = _distanceText(s);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _openDetail(s),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 封面
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 112,
                  height: 96,
                  child: s.coverUrl != null
                      ? Image.network(
                          s.coverUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: AppTheme.primaryLight,
                            child: const Icon(Icons.phishing,
                                color: AppTheme.primary),
                          ),
                        )
                      : Container(
                          color: AppTheme.primaryLight,
                          child: const Icon(Icons.phishing,
                              color: AppTheme.primary),
                        ),
                ),
              ),
              const SizedBox(width: 10),
              // 信息区
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 名称 + 星级
                    Row(
                      children: [
                        if (s.kind == 'shop') ...[
                          Container(
                            margin: const EdgeInsets.only(right: 5),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: AppTheme.violetLight,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text('渔具店',
                                style: TextStyle(
                                    fontSize: 10,
                                    color: AppTheme.violet)),
                          ),
                        ],
                        Expanded(
                          child: Text(s.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold)),
                        ),
                        const Icon(Icons.star,
                            size: 15, color: AppTheme.star),
                        const SizedBox(width: 3),
                        Text(s.rating.toStringAsFixed(1),
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.star)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    // 标签（推荐 / 黑坑 / 电话认证…）
                    if (tags.isNotEmpty)
                      Wrap(
                        spacing: 5,
                        runSpacing: 4,
                        children: tags
                            .map((t) => Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: t.contains('推荐')
                                        ? AppTheme.warningLight
                                        : t.contains('认证')
                                            ? AppTheme.primaryLight
                                            : AppTheme.violetLight,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(t,
                                      style: TextStyle(
                                          fontSize: 10,
                                          color: t.contains('推荐')
                                              ? AppTheme.warning
                                              : t.contains('认证')
                                                  ? AppTheme.primary
                                                  : AppTheme.violet)),
                                ))
                            .toList(),
                      ),
                    const SizedBox(height: 4),
                    // 地址 + 距离
                    Row(
                      children: [
                        const Icon(Icons.location_on_outlined,
                            size: 13, color: Colors.grey),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            s.address.isNotEmpty ? s.address : '地址待补充',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 11.5, color: Colors.grey),
                          ),
                        ),
                        if (distance != null) ...[
                          const SizedBox(width: 6),
                          Text(distance,
                              style: const TextStyle(
                                  fontSize: 11.5,
                                  color: AppTheme.accent,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    // 鱼种 + 评论数
                    Row(
                      children: [
                        const Icon(Icons.set_meal_outlined,
                            size: 13, color: Colors.grey),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            s.fish.isNotEmpty ? s.fish : '鱼种待补充',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 11.5, color: Colors.grey),
                          ),
                        ),
                        const Icon(Icons.chat_bubble_outline,
                            size: 12, color: Colors.grey),
                        const SizedBox(width: 3),
                        Text('${s.commentCount}',
                            style: const TextStyle(
                                fontSize: 11.5, color: Colors.grey)),
                      ],
                    ),
                    const SizedBox(height: 3),
                    // 收费
                    Row(
                      children: [
                        const Icon(Icons.payments_outlined,
                            size: 13, color: Colors.grey),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            s.fee.isNotEmpty ? s.fee : '收费待补充',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 11.5, color: Colors.grey),
                          ),
                        ),
                      ],
                    ),
                    if (s.description.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(s.description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 11.5, color: Colors.black54)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

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
                        color: AppTheme.accent)),
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

  void _openDetail(FishingSpot s) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => SpotDetailScreen(spot: s)),
    );
  }

  /// 添加钓场/渔具店（图4 表单，后台审核后展示）
  Future<void> _openVenueForm() async {
    if (!await _requireLogin()) return;
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PublishVenueScreen()),
    );
    _load();
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
