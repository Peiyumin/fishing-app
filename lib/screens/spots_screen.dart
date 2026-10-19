import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../models/fishing_spot.dart';
import '../services/session_provider.dart';
import '../services/spot_service.dart';
import '../utils/coord_transform.dart';
import '../widgets/center_toast.dart';
import 'auth_screen.dart';
import 'publish_spot_screen.dart';
import 'publish_venue_screen.dart';
import 'spot_detail_screen.dart';

/// 钓点页：双 Tab
///   ① 本地钓场：图2 样式卡片列表（封面 / 星级 / 标签 / 地址 / 距离 / 收费 / 简介）
///   ② 野钓钓点：卫星地图（高德卫星 + 路网），用户可在地图上添加标记，全员实时可见
class SpotsScreen extends StatefulWidget {
  const SpotsScreen({super.key});

  @override
  State<SpotsScreen> createState() => _SpotsScreenState();
}

class _SpotsScreenState extends State<SpotsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final MapController _mapController = MapController();

  List<FishingSpot> _venues = []; // 本地钓场（kind=venue）
  List<FishingSpot> _shops = []; // 渔具店（kind=shop）
  List<FishingSpot> _wild = []; // 野钓点（kind=wild）
  bool _loading = true;
  String _type = '全部';
  final List<String> _types = ['全部', '黑坑', '路亚', '野钓场', '海钓', '渔具店'];

  // 我的当前位置（WGS-84，用于距离计算）
  double? _myLat;
  double? _myLng;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _load();
    _locate();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final spots = await SpotService.fetchSpots();
    if (!mounted) return;
    setState(() {
      _venues = spots.where((s) => s.kind == 'venue').toList();
      _shops = spots.where((s) => s.kind == 'shop').toList();
      _wild = spots.where((s) => s.kind == 'wild').toList();
      _loading = false;
    });
  }

  /// 获取当前位置（仅用于距离展示与地图居中）
  Future<void> _locate() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      if (!mounted) return;
      setState(() {
        _myLat = pos.latitude;
        _myLng = pos.longitude;
      });
      // 卫星地图居中到当前位置（WGS-84 → GCJ-02 后再定位）
      final g = CoordTransform.wgs84ToGcj02(pos.latitude, pos.longitude);
      _mapController.move(LatLng(g[0], g[1]), 13);
    } catch (_) {/* 定位失败时用默认中心 */}
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
        flexibleSpace: Container(
          decoration: const BoxDecoration(gradient: AppTheme.headerGradient),
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: [
            Tab(text: '本地钓场（${_venues.length + _shops.length}）'),
            const Tab(text: '野钓钓点'),
          ],
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
        children: [
          _buildVenueTab(),
          _buildWildTab(),
        ],
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
          child: RefreshIndicator(
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

  // ==================== Tab ② 野钓卫星地图 ====================
  Widget _buildWildTab() {
    // 默认中心：杭州；有定位时用当前位置
    final centerGcj = _myLat != null
        ? LatLng(CoordTransform.wgs84ToGcj02(_myLat!, _myLng!)[0],
            CoordTransform.wgs84ToGcj02(_myLat!, _myLng!)[1])
        : const LatLng(30.2741, 120.1551);

    // 野钓点坐标 WGS-84 → GCJ-02 后再叠加到高德卫星图上
    final markers = _wild.map((s) {
      final g = CoordTransform.wgs84ToGcj02(s.lat, s.lng);
      return Marker(
        point: LatLng(g[0], g[1]),
        width: 38,
        height: 38,
        child: GestureDetector(
          onTap: () => _showWildSheet(s),
          child: const Icon(Icons.location_on,
              color: AppTheme.danger, size: 36),
        ),
      );
    }).toList();

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: centerGcj,
            initialZoom: _myLat != null ? 13 : 8,
          ),
          children: [
            // 高德卫星影像（style=8）
            TileLayer(
              urlTemplate:
                  'https://webst01.is.autonavi.com/appmaptile?x={x}&y={y}&z={z}&lang=zh_cn&size=1&scale=1&style=8',
              userAgentPackageName: 'com.example.fishing_app',
            ),
            // 高德路网标注（style=6，叠加在卫星图上）
            TileLayer(
              urlTemplate:
                  'https://webst01.is.autonavi.com/appmaptile?x={x}&y={y}&z={z}&lang=zh_cn&size=1&scale=1&style=6',
              userAgentPackageName: 'com.example.fishing_app',
            ),
            if (markers.isNotEmpty) MarkerLayer(markers: markers),
          ],
        ),
        // 顶部提示条
        Positioned(
          top: 10,
          left: 12,
          right: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.92),
              borderRadius: BorderRadius.circular(10),
              boxShadow: const [
                BoxShadow(color: Colors.black12, blurRadius: 6)
              ],
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline,
                    size: 15, color: AppTheme.accent),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '红色标记为钓友共享的野钓点（${_wild.length} 个），点击查看详情',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 18),
                  tooltip: '刷新',
                  onPressed: _load,
                ),
              ],
            ),
          ),
        ),
        // 我的位置按钮
        Positioned(
          right: 12,
          bottom: 96,
          child: FloatingActionButton.small(
            backgroundColor: Colors.white,
            foregroundColor: AppTheme.accent,
            tooltip: '我的位置',
            onPressed: _locate,
            child: const Icon(Icons.my_location),
          ),
        ),
        // 添加野钓点（主入口）
        Positioned(
          right: 12,
          bottom: 32,
          child: FloatingActionButton.extended(
            backgroundColor: AppTheme.danger,
            foregroundColor: Colors.white,
            tooltip: '标记野钓点',
            onPressed: () async {
              if (!await _requireLogin()) return;
              if (!mounted) return;
              await Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => const PublishSpotScreen()),
              );
              _load(); // 返回后刷新：新标记全员实时可见
            },
            icon: const Icon(Icons.add_location_alt),
            label: const Text('标记野钓点'),
          ),
        ),
      ],
    );
  }

  /// 地图标记气泡：野钓点简要信息 + 进详情
  void _showWildSheet(FishingSpot s) {
    final distance = _distanceText(s);
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.location_on, color: AppTheme.danger),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(s.name,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                  if (distance != null)
                    Text('距我 $distance',
                        style: const TextStyle(
                            fontSize: 12, color: AppTheme.accent)),
                ],
              ),
              const SizedBox(height: 8),
              Text(s.description.isEmpty ? '钓友暂未填写说明' : s.description,
                  style: const TextStyle(fontSize: 13, color: Colors.black87)),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.star, size: 14, color: AppTheme.star),
                  const SizedBox(width: 3),
                  Text('${s.rating.toStringAsFixed(1)} 分',
                      style: const TextStyle(fontSize: 12)),
                  const SizedBox(width: 14),
                  const Icon(Icons.set_meal_outlined,
                      size: 14, color: Colors.grey),
                  const SizedBox(width: 3),
                  Expanded(
                    child: Text(
                        s.fish.isNotEmpty ? s.fish : '鱼种待补充',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12, color: Colors.grey)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _openDetail(s);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('查看详情'),
                ),
              ),
            ],
          ),
        ),
      ),
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
